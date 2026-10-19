#!/bin/sh
set -eu

KPACKAGETOOL=${KPACKAGETOOL:-kpackagetool6}
PACKAGE_ID=io.github.catprincehq2.desktop-orbit

if ! command -v "$KPACKAGETOOL" >/dev/null 2>&1; then
    printf '%s\n' "Error: $KPACKAGETOOL was not found. Install the KDE Plasma 6 package tools first." >&2
    exit 1
fi

exec "$KPACKAGETOOL" --type Plasma/Applet --remove "$PACKAGE_ID"
