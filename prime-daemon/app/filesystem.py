"""
File browser, move/rename, and delete-to-trash.

Every path-accepting function validates against ALLOWLISTED_ROOTS before
touching anything. Delete never permanently removes — it moves into
~/.prime-trash with a timestamp prefix so it's always recoverable.
"""
import shutil
import time
from pathlib import Path

from app.config import TRASH_DIR, is_path_allowed


class PathNotAllowed(Exception):
    pass


class PathNotFound(Exception):
    pass


def _validate(path_str: str) -> Path:
    path = Path(path_str).expanduser()
    if not is_path_allowed(path):
        raise PathNotAllowed(f"{path} is outside allowlisted roots")
    return path


def list_dir(path_str: str) -> dict:
    path = _validate(path_str)
    if not path.exists():
        raise PathNotFound(str(path))
    if not path.is_dir():
        raise PathNotFound(f"{path} is not a directory")

    entries = []
    for entry in sorted(path.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
        try:
            stat = entry.stat()
            entries.append({
                "name": entry.name,
                "path": str(entry),
                "type": "dir" if entry.is_dir() else "file",
                "size_bytes": stat.st_size if entry.is_file() else None,
                "mtime": int(stat.st_mtime),
            })
        except (PermissionError, OSError):
            continue

    return {"path": str(path), "entries": entries}


def preview(path_str: str) -> dict:
    """Recursive size + file count, used before a delete confirm."""
    path = _validate(path_str)
    if not path.exists():
        raise PathNotFound(str(path))

    total_size = 0
    file_count = 0

    if path.is_file():
        stat = path.stat()
        return {"path": str(path), "size_bytes": stat.st_size, "file_count": 1}

    for p in path.rglob("*"):
        try:
            if p.is_file():
                total_size += p.stat().st_size
                file_count += 1
        except (PermissionError, OSError):
            continue

    return {"path": str(path), "size_bytes": total_size, "file_count": file_count}


def delete(path_str: str) -> dict:
    """Move to trash, never permanent delete."""
    path = _validate(path_str)
    if not path.exists():
        raise PathNotFound(str(path))

    TRASH_DIR.mkdir(parents=True, exist_ok=True)
    dest_name = f"{int(time.time())}__{path.name}"
    dest = TRASH_DIR / dest_name

    shutil.move(str(path), str(dest))
    return {"moved_to": str(dest)}


def move(src_str: str, dst_str: str) -> dict:
    src = _validate(src_str)
    dst = _validate(dst_str)
    if not src.exists():
        raise PathNotFound(str(src))

    shutil.move(str(src), str(dst))
    return {"moved_to": str(dst)}


def rename(path_str: str, new_name: str) -> dict:
    path = _validate(path_str)
    if not path.exists():
        raise PathNotFound(str(path))
    if "/" in new_name or new_name in (".", ".."):
        raise ValueError("Invalid new name")

    dest = path.parent / new_name
    _validate(str(dest))
    path.rename(dest)
    return {"renamed_to": str(dest)}


def validate_for_download(path_str: str) -> Path:
    """Same allowlist check as everything else — used before streaming a file back."""
    path = _validate(path_str)
    if not path.exists():
        raise PathNotFound(str(path))
    if not path.is_file():
        raise ValueError("Path is a directory, not a file")
    return path


def save_upload(target_dir_str: str, filename: str, content: bytes) -> dict:
    """Save uploaded bytes into an allowlisted directory. Never overwrites —
    appends ' (2)', ' (3)', etc. if a file with that name already exists."""
    target_dir = _validate(target_dir_str)
    if not target_dir.exists() or not target_dir.is_dir():
        raise PathNotFound(str(target_dir))

    # Sanitize filename — no path traversal via a crafted upload filename.
    safe_name = Path(filename).name
    if not safe_name or safe_name in (".", ".."):
        raise ValueError("Invalid filename")

    dest = target_dir / safe_name
    if dest.exists():
        stem, suffix = dest.stem, dest.suffix
        counter = 2
        while dest.exists():
            dest = target_dir / f"{stem} ({counter}){suffix}"
            counter += 1

    _validate(str(dest))
    dest.write_bytes(content)
    return {"saved_to": str(dest), "size_bytes": len(content)}
