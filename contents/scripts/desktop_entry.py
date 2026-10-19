#!/usr/bin/env python3
"""Read a launcher's display name and icon from its Desktop Entry section."""
import json
import sys
from pathlib import Path


def unescape(value):
    return (value.replace(r"\s", " ").replace(r"\n", "\n")
            .replace(r"\t", "\t").replace(r"\r", "\r")
            .replace(r"\\", "\\"))


def main(path):
    values = {}
    in_entry = False
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            in_entry = line == "[Desktop Entry]"
            continue
        if in_entry and "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            if key in ("Name", "Icon"):
                values[key] = unescape(value)

    icon = values.get("Icon", "")
    if icon.startswith("/") and Path(icon).is_file():
        icon = Path(icon).as_uri()
    print(json.dumps({"name": values.get("Name", ""), "icon": icon}))


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except (IndexError, OSError, UnicodeError) as error:
        print(json.dumps({"error": str(error)}))
