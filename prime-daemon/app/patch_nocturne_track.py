#!/usr/bin/env python3
import pathlib

TARGET = pathlib.Path.home() / "Projects/prime/prime-daemon/app/commands.py"

OLD_LINE = 'NOCTURNE_TRACK = MUSIC_DIR / "Leave It All To Sink Into Heavy Rain And Thunderstorms - Relax And Sleep In Cozy Car.m4a"'
NEW_LINE = 'NOCTURNE_TRACK = MUSIC_DIR / "🔴 Relaxing Rain Sounds on Tin Roof for Deep Sleep, Rain Sounds for Sleeping, Heavy Rain and Thunder.m4a"'

def main():
    text = TARGET.read_text()
    if NEW_LINE in text:
        print("Already patched — nothing to do.")
        return
    assert OLD_LINE in text, "Anchor line not found. Aborting."
    text = text.replace(OLD_LINE, NEW_LINE)
    TARGET.write_text(text)
    print(f"Patched NOCTURNE_TRACK in {TARGET}")

if __name__ == "__main__":
    main()
