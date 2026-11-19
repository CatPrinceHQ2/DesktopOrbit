#!/usr/bin/env python3
"""Read a launcher's display name and icon from its Desktop Entry section."""
import json
import os
import sys
from pathlib import Path


def resolve_icon(value):
    """Return an icon source Kirigami can load on Plasma and other desktops."""
    value = value.strip()
    if not value:
        return "application-x-executable"

    # Absolute paths and file URLs are accepted, but normalize them to a local
    # file URL only when the target exists. Preserve remote URLs as-is.
    if value.startswith("file://"):
        from urllib.parse import unquote, urlparse
        parsed = urlparse(value)
        value = unquote(parsed.path)
    if os.path.isabs(value):
        path = Path(value)
        return path.resolve().as_uri() if path.is_file() else "application-x-executable"

    # Resolve named icons through the active icon theme using Qt's icon theme
    # search paths; Kirigami can also resolve the unchanged theme name itself.
    try:
        from PySide6.QtGui import QIcon
        from PySide6.QtWidgets import QApplication
        app = QApplication.instance() or QApplication([])
        themed = QIcon.fromTheme(value)
        if not themed.isNull():
            # Keep theme names as names so icon theme changes remain dynamic.
            return value
    except Exception:
        pass
    return value


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
            key, value = key.strip(), value.strip()
            if key in ("Name", "Icon"):
                values[key] = unescape(value)

    icon = resolve_icon(values.get("Icon", ""))
    print(json.dumps({"name": values.get("Name", ""), "icon": icon}))


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except (IndexError, OSError, UnicodeError) as error:
        print(json.dumps({"error": str(error)}))
