# InkWand

Use an iPad with Apple Pencil as a native Linux graphics tablet.

![InkWand running on iPad Pro](demo.gif)

InkWand has two parts:

- `Apps/iPad`: the iPad app, built with `xtool`.
- `Apps/Server`: the Linux tray/server app intended for AppImage distribution.
- `Packages/InkWandCore`: shared protocol, mapping, pairing, settings, and tests.

The server exposes virtual pen, touch, and pad devices through `/dev/uinput`. Wi-Fi discovery supports multiple iPads and multiple computers on the same network, and sessions must authenticate through a trusted pairing record before input is accepted.

## Features

- Apple Pencil input with pressure and tilt.
- Pen and eraser tool modes.
- Native Linux multitouch gestures, including two-finger pinch/zoom in apps such as Krita.
- Pad actions for undo, redo, brush size, opacity, and pan.
- Secure pairing model with one-time codes and persistent trusted peers.
- Global pad rebinding stored in user config.
- Optional launch-at-startup through a user autostart `.desktop` entry.

## Requirements

- Swift 6 for development builds.
- Linux with `/dev/uinput`.
- `iproxy` for USB mode.
- `avahi-publish-service` for Wi-Fi discovery.
- `xtool` for installing the iPad app during development.

On Arch-like systems:

```bash
sudo pacman -S swift libimobiledevice usbmuxd avahi
sudo modprobe uinput
```

InkWand is designed to run as a user-launched AppImage. A distro may still need a one-time udev rule or equivalent local setup to allow the user to access `/dev/uinput`; the app itself does not install a systemd daemon.

## Build

```bash
swift test --package-path Packages/InkWandCore
swift build --package-path Apps/Server -c release --product InkWandServer
cd Apps/iPad
xtool dev run
```

Swift Bundler metadata is defined in `Apps/Server/Bundler.toml`:

```bash
cd Apps/Server
swift bundler bundle InkWandServer
```

If Swift Bundler does not emit an AppImage directly in your environment, use its bundle output as the AppDir input for AppImage tooling.

## Run

During development:

```bash
Apps/Server/.build/release/InkWandServer
```

For headless diagnostics:

```bash
sudo Apps/Server/.build/release/InkWandServer run --pair
```

`--pair` prints a temporary pairing code. The tray app should expose this as “Pair new iPad” in the product UI.

By default the server:

- creates `InkWand Virtual Pen`
- creates `InkWand Touch Surface`
- creates `InkWand Pad`
- listens for Wi-Fi on port `24817`
- publishes `_inkwand._tcp`
- answers UDP discovery with server identity and pairing availability
- rejects input until the iPad authenticates

Useful options:

```bash
InkWandServer run --verbose
InkWandServer run --port 24817 --server-name "Studio Workstation"
InkWandServer run --pair
```

## Wi-Fi Firewall

Wi-Fi needs TCP and UDP port `24817`.

```bash
sudo Apps/Server/.build/release/InkWandServer firewall install
```

To remove the rules:

```bash
sudo Apps/Server/.build/release/InkWandServer firewall uninstall
```

## Launch At Startup

The AppImage product should implement “Launch when system starts” by writing:

```text
~/.config/autostart/inkwand.desktop
```

The entry points to the current AppImage path. If the AppImage is moved, InkWand detects the stale path and asks the user to re-enable launch at startup.

Deleting the AppImage removes the application. User config and optional autostart files remain under standard XDG locations and can be removed from settings.

## iPad App

The app discovers computers on the local network and stores trusted servers independently, so one iPad can be paired with multiple computers and reconnect only to the selected one.

Connection modes:

- `Auto`: use USB when available, otherwise Wi-Fi.
- `USB`: use the USB tunnel only.
- `Wi-Fi`: discover and connect to a trusted server over the local network.

## Troubleshooting

If pen input works but multitouch gestures do not show up in Krita:

- reconnect the iPad app
- make sure Krita is using canvas gestures for touch input
- run the server with `--verbose` and check for `touch began`, `touch ended`, and `session input summary` log lines

If Wi-Fi discovery works but connection hangs, open the firewall port:

```bash
sudo Apps/Server/.build/release/InkWandServer firewall install
```

If `/dev/uinput` is missing:

```bash
sudo modprobe uinput
```

If the server can open `/dev/uinput` only as root, add a local udev rule that grants your user access to `/dev/uinput`.
