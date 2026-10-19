#!/usr/bin/env python3
"""Build a distributable Plasma applet package from this repository."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "Desktop-Orbit.plasmoid"
INCLUDED = ("metadata.json", "contents", "LICENSE")


def main():
    with ZipFile(OUTPUT, "w", ZIP_DEFLATED) as archive:
        for relative in INCLUDED:
            path = ROOT / relative
            paths = [path] if path.is_file() else sorted(path.rglob("*"))
            for item in paths:
                if item.is_file() and "__pycache__" not in item.parts and item.suffix != ".pyc":
                    archive.write(item, item.relative_to(ROOT))
    print(f"Built {OUTPUT}")


if __name__ == "__main__":
    main()
