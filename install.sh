#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ID=io.github.catprincehq2.desktop-orbit
KPACKAGETOOL=${KPACKAGETOOL:-kpackagetool6}

if ! command -v "$KPACKAGETOOL" >/dev/null 2>&1; then
    printf '%s\n' "Error: $KPACKAGETOOL was not found. Install the KDE Plasma 6 package tools first." >&2
    exit 1
fi

if "$KPACKAGETOOL" --type Plasma/Applet --list 2>/dev/null | grep -F -x "$PACKAGE_ID" >/dev/null; then
    ACTION=--upgrade
else
    ACTION=--install
fi

exec "$KPACKAGETOOL" --type Plasma/Applet "$ACTION" "$ROOT"
