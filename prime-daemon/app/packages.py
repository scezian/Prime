"""
Package management via paru (AUR-aware, matches EndeavourOS setup).

Install/uninstall need root for the pacman step. paru internally calls
sudo for that. Rather than juggling a fragile cached sudo credential
across separate subprocess calls (which doesn't survive across
processes without a real terminal), scez-2 has a scoped sudoers rule
allowing passwordless `pacman` only (see setup.sh) — so paru's
internal sudo calls just succeed without ever prompting.

Install/uninstall run as background jobs rather than blocking the HTTP
request for up to 10 minutes. A job dict is kept in memory (lost on
daemon restart). The app polls GET /packages/jobs/{id} for live status.

paru/pacman only print their normal progress bar (percentages, sizes,
carriage-return redraws) when stdout is attached to a real terminal —
piped straight to subprocess.PIPE, they silently drop to a bare
"downloading..." line with no numbers at all. To get real progress we
run the command inside a pty (see _run_job) so pacman thinks it's
talking to a terminal.

Two output shapes to handle, confirmed against real output on scez-2:
  - Single package, no deps: one line per download —
        pkgname   2.4 MiB   418 KiB/s 02:58 [----------] 3%
  - Multiple packages (deps pulled in): a live table, one line per
    in-flight download plus an aggregate line —
        Total ( 0/49)   5.0 MiB  1329 KiB/s 08:21 [----] 0%
    The Total line is what we want for an overall progress bar; the
    per-package lines are ignored once a Total line has been seen,
    since tracking one specific dependency's progress would be a
    misleading, jumpy stand-in for the whole job.
"""
import re
import subprocess
import threading
import uuid


class PackageManagerError(Exception):
    pass


def search_package(query: str, limit: int = 20) -> dict:
    try:
        proc = subprocess.run(
            ["paru", "-Ss", "--noconfirm", query],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        raise PackageManagerError("paru not found on this system")
    except subprocess.TimeoutExpired:
        raise PackageManagerError("paru search timed out")

    results = []
    lines = proc.stdout.splitlines()
    i = 0
    while i < len(lines):
        header = lines[i]
        if header and not header[0].isspace():
            parts = header.split()
            name_repo = parts[0] if parts else ""
            version = parts[1] if len(parts) > 1 else ""
            installed = "[installed]" in header
            description = ""
            if i + 1 < len(lines) and lines[i + 1].startswith((" ", "\t")):
                description = lines[i + 1].strip()
                i += 1
            results.append({
                "package": name_repo,
                "version": version,
                "installed": installed,
                "description": description,
            })
        i += 1

    query_lower = query.lower()

    def relevance(r):
        name = r["package"].split("/")[-1].lower()
        if name == query_lower:
            return 0
        if name.startswith(query_lower):
            return 1
        if query_lower in name:
            return 2
        return 3

    results.sort(key=lambda r: (relevance(r), len(r["package"])))
    total = len(results)
    results = results[:limit]

    return {"query": query, "total_matches": total, "results": results}


def list_installed() -> dict:
    """Explicitly-installed packages (not pulled in as a dependency),
    tagged aur/extra based on whether pacman considers them 'foreign'."""
    try:
        explicit = subprocess.run(
            ["pacman", "-Qe"], capture_output=True, text=True, timeout=15
        )
        foreign = subprocess.run(
            ["pacman", "-Qm"], capture_output=True, text=True, timeout=15
        )
    except FileNotFoundError:
        raise PackageManagerError("pacman not found on this system")
    except subprocess.TimeoutExpired:
        raise PackageManagerError("listing installed packages timed out")

    foreign_names = set()
    for line in foreign.stdout.splitlines():
        parts = line.split()
        if parts:
            foreign_names.add(parts[0])

    packages = []
    for line in explicit.stdout.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        name, version = parts[0], parts[1]
        repo = "aur" if name in foreign_names else "extra"
        packages.append({
            "package": f"{repo}/{name}",
            "version": version,
            "installed": True,
            "description": "",
        })

    packages.sort(key=lambda p: p["package"])
    return {"packages": packages, "total": len(packages)}


# ---- Async job tracking for install/uninstall ----

_jobs: dict[str, dict] = {}
_jobs_lock = threading.Lock()

_JOB_TIMEOUT_SECONDS = 600

_UNIT_MULT = {"KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3}

# Strip ANSI color codes (CSI, e.g. "\x1b[1;33m") and OSC sequences
# (e.g. kitty's shell-integration markers "\x1b]3008;end=...\x1b\\").
_ANSI_CSI_RE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
_ANSI_OSC_RE = re.compile(r"\x1b\][^\x1b\x07]*(?:\x07|\x1b\\)")

# Aggregate line shown when multiple packages are downloading at once:
#   Total ( 0/49)   5.0 MiB  1329 KiB/s 08:21 [----] 0%
_TOTAL_LINE_RE = re.compile(
    r"Total\s*\(\s*\d+\s*/\s*\d+\s*\)\s+"
    r"(?P<size>[\d.]+)\s*(?P<unit>[KMG]iB).*?(?P<percent>\d{1,3})%"
)

# A single package's own progress line (used when there's no Total line,
# i.e. installing one package with no new dependencies):
#   pkgname   2.4 MiB   418 KiB/s 02:58 [----] 3%
_PACKAGE_LINE_RE = re.compile(
    r"(?P<size>[\d.]+)\s*(?P<unit>[KMG]iB).*?(?P<percent>\d{1,3})%"
)

# Printed once before downloads start: "Total Download Size:  655.21 MiB"
_TOTAL_DECLARED_RE = re.compile(
    r"Total Download Size:\s+(?P<size>[\d.]+)\s*(?P<unit>[KMG]iB)"
)

# Lines indicating we've moved past downloading into the local
# verify/install/remove phase.
_POST_DOWNLOAD_MARKERS = (
    "checking keys",
    "checking package integrity",
    "checking for file conflicts",
    "loading package files",
    "processing package changes",
)


def _strip_ansi(s: str) -> str:
    s = _ANSI_OSC_RE.sub("", s)
    s = _ANSI_CSI_RE.sub("", s)
    return s


def _is_aur_package(package: str) -> bool:
    """True if pacman doesn't know this package as a repo package --
    i.e. it can only come from the AUR. Checked once at job creation
    so the whole job's progress model (bytes vs phases) is decided
    upfront rather than guessed at from output shape."""
    proc = subprocess.run(
        ["pacman", "-Si", package],
        capture_output=True, text=True, timeout=10,
    )
    return proc.returncode != 0


_AUR_PHASES = [
    ("resolving dependencies", "Resolving dependencies"),
    ("downloading pkgbuilds", "Fetching PKGBUILD"),
    ("retrieving sources", "Downloading sources"),
    ("validating source files", "Verifying sources"),
    ("starting prepare", "Preparing build"),
    ("starting build", "Building package"),
    ("starting package", "Packaging"),
    ("checking keys", "Checking package integrity"),
    ("checking for file conflicts", "Checking for conflicts"),
    ("installing", "Installing"),
]


def _new_job(action: str, package: str) -> str:
    job_id = uuid.uuid4().hex[:12]
    with _jobs_lock:
        _jobs[job_id] = {
            "id": job_id,
            "action": action,
            "package": package,
            # pending -> downloading -> installing -> success | failed
            "status": "pending",
            "downloaded_bytes": None,
            "total_bytes": None,
            "returncode": None,
            "error": None,
            "is_aur": _is_aur_package(package),
            "phase_index": 0,
            "phase_total": len(_AUR_PHASES),
            "phase_label": "Queued",
            # internal only, not returned to the app
            "_seen_total_line": False,
        }
    return job_id


def get_job(job_id: str) -> dict:
    with _jobs_lock:
        job = _jobs.get(job_id)
        if job is None:
            raise PackageManagerError(f"unknown job id: {job_id}")
        job = dict(job)
        job.pop("_seen_total_line", None)
        return job


def _iter_raw_lines(fd):
    """Yields logical lines from a pty master fd, splitting on both
    '\\n' (normal output) and '\\r' (progress-bar redraws), since
    pacman uses \\r to update its progress lines in place."""
    buf = []
    while True:
        try:
            chunk = fd.read(1)
        except OSError:
            break
        if not chunk:
            break
        if chunk in ("\n", "\r"):
            if buf:
                yield "".join(buf)
                buf = []
        else:
            buf.append(chunk)
    if buf:
        yield "".join(buf)


def _apply_line(job_id: str, raw_line: str):
    line = _strip_ansi(raw_line).strip()
    if not line:
        return

    with _jobs_lock:
        job = _jobs[job_id]

        if job["is_aur"]:
            lower = line.lower()
            for i, (marker, label) in enumerate(_AUR_PHASES):
                if marker in lower and i >= job["phase_index"]:
                    job["phase_index"] = i
                    job["phase_label"] = label
                    if job["status"] not in ("success", "failed"):
                        job["status"] = "installing" if i >= 7 else "downloading"
                    break
            return

        m = _TOTAL_DECLARED_RE.search(line)
        if m and job["total_bytes"] is None:
            size = float(m.group("size"))
            job["total_bytes"] = size * _UNIT_MULT.get(m.group("unit"), 1)
            return

        if any(marker in line.lower() for marker in _POST_DOWNLOAD_MARKERS):
            if job["status"] != "failed":
                job["status"] = "installing"
            return

        if "installing" in line.lower() or "removing" in line.lower() or "upgrading" in line.lower():
            if job["status"] != "failed":
                job["status"] = "installing"
            return

        m = _TOTAL_LINE_RE.search(line)
        if m:
            job["_seen_total_line"] = True
            size = float(m.group("size"))
            downloaded = size * _UNIT_MULT.get(m.group("unit"), 1)
            if job["status"] not in ("installing", "success", "failed"):
                job["status"] = "downloading"
            job["downloaded_bytes"] = downloaded
            return

        if job["_seen_total_line"]:
            # Once we've seen the aggregate line, ignore individual
            # per-package lines — they'd make the bar jump around.
            return

        m = _PACKAGE_LINE_RE.search(line)
        if m:
            size = float(m.group("size"))
            unit = m.group("unit")
            percent = int(m.group("percent"))
            downloaded = size * _UNIT_MULT.get(unit, 1)
            if job["status"] not in ("installing", "success", "failed"):
                job["status"] = "downloading"
            job["downloaded_bytes"] = downloaded
            if job["total_bytes"] is None and percent > 0:
                job["total_bytes"] = downloaded / (percent / 100)


_DEBUG_LOG_PATH = "/tmp/prime-daemon-job-debug.log"


def _run_job(job_id: str, cmd: list[str]):
    with _jobs_lock:
        _jobs[job_id]["status"] = "downloading"

    import fcntl
    import os
    import pty
    import struct
    import termios

    tail_lines: list[str] = []

    try:
        pid, fd = pty.fork()
    except OSError as e:
        with _jobs_lock:
            _jobs[job_id]["status"] = "failed"
            _jobs[job_id]["error"] = f"failed to allocate pty: {e}"
        return

    if pid == 0:
        # Child: replace this process with the paru command. A pty
        # convinces paru/pacman it has a real terminal, so it renders
        # its normal progress bar instead of the bare non-TTY fallback.
        # A systemd service normally has no TERM set at all, which can
        # make ncurses-based progress rendering fall back to plain
        # output — force one explicitly.
        os.environ["TERM"] = "xterm-256color"
        try:
            os.execvp(cmd[0], cmd)
        except FileNotFoundError:
            os._exit(127)

    # Parent: pty.fork() leaves the new pty at a 0x0 window size, which
    # some progress-bar rendering treats as "not a usable terminal" and
    # skips entirely. Give it a real size before the child gets going.
    try:
        winsize = struct.pack("HHHH", 50, 220, 0, 0)  # rows, cols, xpixel, ypixel
        fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
    except OSError:
        pass  # best-effort; worse case we're back to no progress bar

    debug_log = None
    try:
        debug_log = open(_DEBUG_LOG_PATH, "w", errors="replace")
        debug_log.write(f"=== job {job_id}: {' '.join(cmd)} ===\n")
    except OSError:
        pass

    # Parent: read from the pty master end, line by line.
    with os.fdopen(fd, "r", errors="replace") as reader:
        try:
            for raw_line in _iter_raw_lines(reader):
                if debug_log:
                    debug_log.write(raw_line + "\n")
                    debug_log.flush()
                tail_lines.append(raw_line.strip())
                if len(tail_lines) > 30:
                    tail_lines.pop(0)
                try:
                    _apply_line(job_id, raw_line)
                except Exception:
                    # A parsing hiccup shouldn't kill the whole job —
                    # worst case we just miss a progress update.
                    pass
        except OSError:
            # Common once the child exits and closes its end of the pty.
            pass
        finally:
            if debug_log:
                debug_log.close()

    _, status = os.waitpid(pid, 0)
    returncode = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1

    with _jobs_lock:
        job = _jobs[job_id]
        job["returncode"] = returncode
        if returncode == 0:
            job["status"] = "success"
            if job["total_bytes"]:
                job["downloaded_bytes"] = job["total_bytes"]
        else:
            job["status"] = "failed"
            clean_tail = [_strip_ansi(l).strip() for l in tail_lines if _strip_ansi(l).strip()]
            job["error"] = "\n".join(clean_tail[-15:]) or f"exited with code {returncode}"


def install_package_async(package: str) -> str:
    job_id = _new_job("install", package)
    thread = threading.Thread(
        target=_run_job,
        args=(job_id, ["paru", "-S", "--noconfirm", package]),
        daemon=True,
    )
    thread.start()
    return job_id


def uninstall_package_async(package: str) -> str:
    job_id = _new_job("uninstall", package)
    thread = threading.Thread(
        target=_run_job,
        args=(job_id, ["paru", "-Rns", "--noconfirm", package]),
        daemon=True,
    )
    thread.start()
    return job_id
