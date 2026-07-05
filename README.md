# InkWand

Use an iPad with Apple Pencil as a native Linux graphics tablet.

![InkWand running on iPad Pro](demo.gif)

InkWand has two parts:

- `InkWand`: the iPad app, built with `xtool`.
- `InkWandServer`: the Linux server, written in Swift, exposing virtual pen, touch, and pad devices through `/dev/uinput`.

The server supports both USB and Wi-Fi. Monitor/output mapping is left to the desktop environment, like with a real tablet.

## Features

- Apple Pencil input with pressure and tilt.
- Pen and eraser tool modes.
- Native Linux multitouch gestures, including two-finger pinch/zoom in apps such as Krita.
- Pad actions for undo, redo, brush size, and opacity.
- USB and Wi-Fi transport with low-latency TCP settings.

## Requirements

- Swift 6
- Linux with `/dev/uinput`
- `iproxy` for USB mode
- `avahi-publish-service` for Wi-Fi discovery
- `xtool` for installing the iPad app

On Arch-like systems:

```bash
sudo pacman -S swift libimobiledevice usbmuxd avahi
sudo modprobe uinput
```

## Build

```bash
swift test
swift build -c release --product InkWandServer
xtool dev run
```

## Run

```bash
sudo .build/release/InkWandServer
```

By default the server:

- creates `InkWand Virtual Pen`
- creates `InkWand Touch Surface`
- creates `InkWand Pad`
- enables USB through `iproxy`
- listens for Wi-Fi on port `24817`
- publishes `_inkwand._tcp`
- reconnects automatically

On X11, InkWand tries to map the virtual pen and touch devices to the full desktop during the first input events. On Wayland, mapping is compositor-managed.

Useful options:

```bash
InkWandServer --verbose
InkWandServer --port 24817
```

## Wi-Fi Firewall

Wi-Fi needs TCP and UDP port `24817`.

```bash
sudo .build/release/InkWandServer firewall install
```

To remove the rules:

```bash
sudo .build/release/InkWandServer firewall uninstall
```

## Systemd Service

Install:

```bash
sudo .build/release/InkWandServer service install
sudo systemctl enable --now inkwand-server.service
```

The service installer also writes an input udev rule at `/etc/udev/rules.d/90-inkwand-input.rules`. It grants access to `/dev/uinput` and groups the InkWand pen, touch, and pad devices for libinput.

Logs:

```bash
journalctl -u inkwand-server.service -f
```

Uninstall:

```bash
sudo .build/release/InkWandServer service uninstall
```

## iPad App

The app has three modes:

- `Auto`: use USB when available, otherwise Wi-Fi.
- `USB`: use the USB tunnel only.
- `Wi-Fi`: discover and connect to the server over the local network.

You can open the app and server in any order.

## Troubleshooting

If pen input works but multitouch gestures do not show up in Krita:

- restart `InkWandServer` after installing or updating the service rule
- reconnect the iPad app
- make sure Krita is using canvas gestures for touch input
- run the server with `--verbose` and check for `touch began`, `touch ended`, and `session input summary` log lines

If Wi-Fi discovery works but connection hangs, open the firewall port:

```bash
sudo .build/release/InkWandServer firewall install
```

If `/dev/uinput` is missing:

```bash
sudo modprobe uinput
```

If the server can open `/dev/uinput` only as root, install the service or add an equivalent udev rule for your system.
