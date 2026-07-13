"""
Prime daemon — laptop-side API for the Prime Android app.

Run with: uvicorn app.main:app --host <tailscale-ip> --port 8420
(systemd unit handles this in production — see prime-daemon.service)
"""
import shutil
import socket
import time
from datetime import timedelta

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.auth import verify_token
from app.commands import COMMANDS, SCREENSHOT_CACHE
from app.config import ALLOWLISTED_ROOTS
from app import filesystem, packages, media

app = FastAPI(title="Prime Daemon")

_BOOT_TIME = time.time()


@app.get("/health")
def health():
    """Unauthenticated — just confirms the daemon is reachable at all."""
    return {"ok": True, "hostname": socket.gethostname()}


@app.get("/status", dependencies=[Depends(verify_token)])
def status():
    disk = shutil.disk_usage("/")
    uptime_seconds = int(time.time() - _BOOT_TIME)

    return {
        "hostname": socket.gethostname(),
        "daemon_uptime": str(timedelta(seconds=uptime_seconds)),
        "disk": {
            "total_gb": round(disk.total / 1e9, 1),
            "used_gb": round(disk.used / 1e9, 1),
            "free_gb": round(disk.free / 1e9, 1),
        },
        "allowlisted_roots": [str(p) for p in ALLOWLISTED_ROOTS],
    }


@app.get("/commands", dependencies=[Depends(verify_token)])
def list_commands():
    return {
        "commands": [
            {
                "id": cmd_id,
                "name": cmd["name"],
                "description": cmd["description"],
                "category": cmd["category"],
                "needs_confirm": cmd["needs_confirm"],
            }
            for cmd_id, cmd in COMMANDS.items()
        ]
    }


@app.post("/commands/{command_id}/run", dependencies=[Depends(verify_token)])
def run_command(command_id: str):
    cmd = COMMANDS.get(command_id)
    if cmd is None:
        raise HTTPException(status_code=404, detail=f"Unknown command: {command_id}")

    try:
        result = cmd["run"]()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Command failed: {e}")

    return {"command_id": command_id, "result": result}


@app.get("/commands/screenshot/image", dependencies=[Depends(verify_token)])
def commands_screenshot_image():
    if not SCREENSHOT_CACHE.exists():
        raise HTTPException(status_code=404, detail="No screenshot captured yet — run the Screenshot command first")
    return FileResponse(SCREENSHOT_CACHE)


# ---- Filesystem ----

@app.get("/fs/list", dependencies=[Depends(verify_token)])
def fs_list(path: str):
    try:
        return filesystem.list_dir(path)
    except filesystem.PathNotAllowed as e:
        raise HTTPException(status_code=403, detail=str(e))
    except filesystem.PathNotFound as e:
        raise HTTPException(status_code=404, detail=str(e))


@app.get("/fs/preview", dependencies=[Depends(verify_token)])
def fs_preview(path: str):
    try:
        return filesystem.preview(path)
    except filesystem.PathNotAllowed as e:
        raise HTTPException(status_code=403, detail=str(e))
    except filesystem.PathNotFound as e:
        raise HTTPException(status_code=404, detail=str(e))


class DeleteBody(BaseModel):
    path: str


@app.post("/fs/delete", dependencies=[Depends(verify_token)])
def fs_delete(body: DeleteBody):
    try:
        return filesystem.delete(body.path)
    except filesystem.PathNotAllowed as e:
        raise HTTPException(status_code=403, detail=str(e))
    except filesystem.PathNotFound as e:
        raise HTTPException(status_code=404, detail=str(e))


class MoveBody(BaseModel):
    src: str
    dst: str


@app.post("/fs/move", dependencies=[Depends(verify_token)])
def fs_move(body: MoveBody):
    try:
        return filesystem.move(body.src, body.dst)
    except filesystem.PathNotAllowed as e:
        raise HTTPException(status_code=403, detail=str(e))
    except filesystem.PathNotFound as e:
        raise HTTPException(status_code=404, detail=str(e))


class RenameBody(BaseModel):
    path: str
    new_name: str


@app.post("/fs/rename", dependencies=[Depends(verify_token)])
def fs_rename(body: RenameBody):
    try:
        return filesystem.rename(body.path, body.new_name)
    except filesystem.PathNotAllowed as e:
        raise HTTPException(status_code=403, detail=str(e))
    except filesystem.PathNotFound as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/fs/download", dependencies=[Depends(verify_token)])
def fs_download(path: str):
    try:
        file_path = filesystem.validate_for_download(path)
    except filesystem.PathNotAllowed as e:
        raise HTTPException(status_code=403, detail=str(e))
    except filesystem.PathNotFound as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return FileResponse(file_path, filename=file_path.name)


@app.post("/fs/upload", dependencies=[Depends(verify_token)])
async def fs_upload(target_dir: str = Form(...), file: UploadFile = File(...)):
    try:
        content = await file.read()
        return filesystem.save_upload(target_dir, file.filename, content)
    except filesystem.PathNotAllowed as e:
        raise HTTPException(status_code=403, detail=str(e))
    except filesystem.PathNotFound as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ---- Packages ----

@app.get("/packages/installed", dependencies=[Depends(verify_token)])
def packages_installed():
    try:
        return packages.list_installed()
    except packages.PackageManagerError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/packages/search", dependencies=[Depends(verify_token)])
def packages_search(query: str, limit: int = 20):
    try:
        return packages.search_package(query, limit=limit)
    except packages.PackageManagerError as e:
        raise HTTPException(status_code=500, detail=str(e))


class InstallBody(BaseModel):
    package: str


@app.post("/packages/install", dependencies=[Depends(verify_token)])
def packages_install(body: InstallBody):
    try:
        return packages.install_package(body.package)
    except packages.PackageManagerError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/packages/uninstall", dependencies=[Depends(verify_token)])
def packages_uninstall(body: InstallBody):
    try:
        return packages.uninstall_package(body.package)
    except packages.PackageManagerError as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---- Media / Volume ----

@app.get("/media/now-playing", dependencies=[Depends(verify_token)])
def media_now_playing():
    try:
        return media.now_playing()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/media/play-pause", dependencies=[Depends(verify_token)])
def media_play_pause():
    try:
        return media.play_pause()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/media/next", dependencies=[Depends(verify_token)])
def media_next():
    try:
        return media.next_track()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/media/previous", dependencies=[Depends(verify_token)])
def media_previous():
    try:
        return media.previous_track()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/audio/volume", dependencies=[Depends(verify_token)])
def audio_get_volume():
    try:
        return media.get_volume()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


class VolumeBody(BaseModel):
    level: int


@app.post("/audio/volume", dependencies=[Depends(verify_token)])
def audio_set_volume(body: VolumeBody):
    try:
        return media.set_volume(body.level)
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/audio/mute-toggle", dependencies=[Depends(verify_token)])
def audio_toggle_mute():
    try:
        return media.toggle_mute()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/media/art", dependencies=[Depends(verify_token)])
def media_art(file_url: str):
    try:
        path = media.resolve_art_path(file_url)
    except media.ControlError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return FileResponse(path)


@app.get("/display/brightness", dependencies=[Depends(verify_token)])
def display_get_brightness():
    try:
        return media.get_brightness()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


class BrightnessBody(BaseModel):
    level: int


@app.post("/display/brightness", dependencies=[Depends(verify_token)])
def display_set_brightness(body: BrightnessBody):
    try:
        return media.set_brightness(body.level)
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/keyboard/backlight", dependencies=[Depends(verify_token)])
def keyboard_get_backlight():
    try:
        return media.get_kbd_backlight()
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))


class KbdBacklightBody(BaseModel):
    level: int


@app.post("/keyboard/backlight", dependencies=[Depends(verify_token)])
def keyboard_set_backlight(body: KbdBacklightBody):
    try:
        return media.set_kbd_backlight(body.level)
    except media.ControlError as e:
        raise HTTPException(status_code=500, detail=str(e))
