#!/usr/bin/env python3
"""List PulseAudio-compatible output sinks for the soundwave selector."""
import json
import subprocess


def main():
    default = subprocess.check_output(["pactl", "get-default-sink"], text=True, timeout=3).strip()
    sinks = json.loads(subprocess.check_output(["pactl", "-f", "json", "list", "sinks"], text=True, timeout=4))
    print(json.dumps({
        "default": default,
        "sinks": [{"name": item["name"], "description": item.get("description") or item["name"]} for item in sinks],
    }, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
