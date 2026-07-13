"""
Package management via paru (AUR-aware, matches EndeavourOS setup).

Install/uninstall need root for the pacman step. paru internally calls
sudo for that. Rather than juggling a fragile cached sudo credential
across separate subprocess calls (which doesn't survive across
processes without a real terminal), scez-2 has a scoped sudoers rule
allowing passwordless `pacman` only (see setup.sh) — so paru's
internal sudo calls just succeed without ever prompting.
"""
import subprocess


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


def install_package(package: str) -> dict:
    try:
        proc = subprocess.run(
            ["paru", "-S", "--noconfirm", package],
            capture_output=True,
            text=True,
            timeout=600,
        )
    except FileNotFoundError:
        raise PackageManagerError("paru not found on this system")
    except subprocess.TimeoutExpired:
        raise PackageManagerError("install timed out after 10 minutes")

    return {
        "package": package,
        "returncode": proc.returncode,
        "stdout": proc.stdout[-4000:],
        "stderr": proc.stderr[-4000:],
    }


def uninstall_package(package: str) -> dict:
    try:
        proc = subprocess.run(
            ["paru", "-Rns", "--noconfirm", package],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except FileNotFoundError:
        raise PackageManagerError("paru not found on this system")
    except subprocess.TimeoutExpired:
        raise PackageManagerError("uninstall timed out after 2 minutes")

    return {
        "package": package,
        "returncode": proc.returncode,
        "stdout": proc.stdout[-4000:],
        "stderr": proc.stderr[-4000:],
    }
