# Installation

Desktop Orbit is a Plasma 6 widget. It is packaged as a Plasma applet and does not need a distribution-specific installer. These instructions apply to Linux and other systems that provide KDE Plasma 6 and the KDE package tool.

This package uses the plugin ID `io.github.catprincehq2.desktop-orbit`, based on the GitHub account `CatPrinceHQ2`. Plasma uses this ID to distinguish this widget from other installed widgets.

## Install from a GitHub release

1. Download `Desktop-Orbit.plasmoid` from the project's Releases page.
2. Open a terminal in the download folder and run:

   ```sh
   kpackagetool6 --type Plasma/Applet --install ./Desktop-Orbit.plasmoid
   ```

   To update an existing installation, use `--upgrade` instead of `--install`.
3. Right-click the desktop, enter edit mode, choose **Add or Manage Widgets**, search for **Desktop Orbit**, and add it to the desktop.

## Install from source

Clone or download this repository, then run:

```sh
./install.sh
```

Or install directly with KDE's package tool:

```sh
kpackagetool6 --type Plasma/Applet --install .
```

The `install.sh` script upgrades the applet if this package ID is already installed. To remove it, run `./uninstall.sh`.

## Build a release package

Python 3 is used only to create the archive; no third-party Python modules are required.

```sh
./build-package.py
```

This creates `Desktop-Orbit.plasmoid` in the repository root. Upload that file to a GitHub Release for end users.

## Runtime requirements

- KDE Plasma 6.0 or newer and `kpackagetool6`.
- Python 3 and NumPy for soundwave mode.
- `pactl` and `parec` for audio sink discovery and audio capture. These are commonly provided by PulseAudio client utilities or a PipeWire PulseAudio compatibility package.
- `gio` to launch selected `.desktop` applications.
- Network access to Open-Meteo for weather data.

Soundwave mode is optional; other widget modes do not need the audio utilities or NumPy. Package names vary by operating system and distribution, so install these dependencies from the system's package repositories.

## Compatibility

The package targets Plasma 6. It is not compatible with Plasma 5. Plasma must be installed and running as the desktop shell; installing KDE applications alone is not sufficient.
