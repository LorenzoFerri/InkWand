# InkWand

Use an iPad with Apple Pencil as a native Linux graphics tablet.

![InkWand running on iPad Pro](demo.gif)

InkWand has two parts:

- `InkWand`: the iPad app, built with `xtool`.
- `InkWandServer`: the Linux server, written in Swift, exposing a virtual pen through `/dev/uinput`.

The server supports both USB and Wi-Fi. Monitor/output mapping is left to the desktop environment, like with a real tablet.

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
- enables USB through `iproxy`
- listens for Wi-Fi on port `24817`
- publishes `_inkwand._tcp`
- reconnects automatically

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

If Wi-Fi discovery works but connection hangs, open the firewall port:

```bash
sudo .build/release/InkWandServer firewall install
```

If `/dev/uinput` is missing:

```bash
sudo modprobe uinput
```
