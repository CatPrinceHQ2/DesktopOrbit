# Desktop Orbit

## Overview

This is my app, Desktop Orbit. Your icons will orbit around the screen in the default mode, the Ellipse mode, but there are some other things to note as well.

## Features

- Here's a fun one; Soundwave mode. All the icons will line up in the center. Play music through the selected sink (you select that on the middle menu) and they will bounce around to it!
- Weather display. I thought that having weather in the center might be useful because I personally wanted that. I also.. didn't include a way to dismiss it unless you minimize the entire center menu. Sorry.
- Rpm slider will make it auto spin.
- ANY shape you can think of you can use by typing in graphing equations in the typebox. It uses like, a basic math parser, so not literally any, but enough of them.

## Demonstration

Click this to see the demonstration (compressed, 9mb for Github)
https://github.com/user-attachments/assets/fb1be07f-09c7-42b9-90bb-aad4f2898a99

Click this to..
[Download the full-quality version (62 MB)](Desktop%20Orbit%20Demonstration.mp4)

## Requirements

- KDE Plasma 6.8.0 was tested. I can't say for newer or older versions.
- An optional dependency would be EasyEffects, as that allows you to tune your audio and also compare Desktop Orbit's soundwave to EasyEffects's soundwave. Additionally I would say this depends on you having atleast 10 different apps on your desktop, or else it starts looking like a polygon rather than a real circle or ellipse or sine wave depending on the option you chose.

## Installation

See [INSTALL.md](INSTALL.md) for source and release-package installation instructions.

## Usage

When you add the widget it should be screenwide, if not, then adjust it's size to fit all four corners of your screen. I don't know how it behave on vertical monitors. You might have to adjust it in code for that to work. Anyways, when you open into it, it should have the weather and the options panel open. You can change the equation there and the speed and all that, then minimize it when your done. Option to hide your location on the weather app incase you are screensharing as well.

## Configuration

Allows for changing of shape of icon path, adding icons, removing icons,

## Troubleshooting

If you keep accidentally moving the widget, right-click an empty part of the desktop and turn on **Lock Widgets** in Plasma. To unlock it later, open the same desktop menu and turn **Lock Widgets** off. Desktop Orbit also only starts spinning when you drag close to an icon path; controls and empty areas wont start a spin.

If in soundwave mode the icons won't settle back to the center, set spin the soundwave or set rpm to 1 as a permanent fix.

## Contributing

If you notice an issue, make an issue on github, and then email me at catprincehq@gmail.com. That way it will be nearly impossible for me to not notice you. If i somehow don't see it within two days, my discord is catprincehq as well.

## License

Desktop Orbit is open source under the [GNU General Public License v3.0 or later](LICENSE).
