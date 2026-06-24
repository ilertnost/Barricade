# Barricade

Self-hosted messenger (LAN alpha, will be VPS-hosted). Go server + Flutter client.

## Features

- Text messaging, edit, delete via WebSocket
- Photo/video from gallery, camera capture, voice messages, video circles
- File sharing (any format, up to 2 GB)
- Audio player with queue, repeat, shuffle, background playback
- Channels: DM, group, public/private guilds
- Material You themes (system/light/dark + accent color)
- Audio/video calls (1-on-1) + screen sharing (1080/60, PC→Android) + voice rooms (mesh)
- Mute channels/DMs, blacklist users
- Password recovery via recovery phrase
- Contacts: add/remove/search
- Desktop-adaptive UI: two-pane master/detail + navigation rail on wide windows, bottom nav on narrow
- Telegram-style input bar: morphing send/record button
- Russian + English interface
- Linux desktop build (Arch Linux, KDE 6, Wayland/X11)

## Network Configuration

Server runs on the local network and listens on `0.0.0.0:8080`.  
**Current server IP**: `192.168.0.103:8080` (Redmi 13C).

To change the server address:
- **Server**: Edit `server/cmd/server/main.go` → `addr` variable (default `:8080`).
- **Client**: Edit `client/lib/config.dart` → `serverUrl` and `wsUrl`.

If deploying on a different machine, change both files accordingly.

## Architecture

```
Barricade/
├── server/      # Go backend (SQLite, WebSocket hub, HTTP API)
└── client/      # Flutter app (Material 3, dark theme)
```

Currently alpha — server runs on an Android phone (ARM64) in LAN. Future builds will run on a VPS/host for remote access.

## Branches

- **Android** — primary mobile target (A_Barricade)
- **Linux** — desktop Linux (Arch, KDE 6, GCC 16)
- **Windows** — desktop Windows (W_Barricade)

## Quick Start

### Server (Android ARM64)

```bash
cd server
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o barricade-server-arm64 ./cmd/server
adb push barricade-server-arm64 /data/local/tmp/
adb shell "DATA_DIR=/data/local/tmp/bcdata PORT=8080 nohup /data/local/tmp/barricade-server-arm64 &"
```

### Client (Android)

```bash
cd client
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Client (Linux)

```bash
cd client
flutter build linux --release
./build/linux/x64/release/bundle/privchat
```

Config: `client/lib/config.dart` — set `serverUrl` to your server IP.

## API

- `POST /api/auth/register` — register (optional `recovery_phrase`)
- `POST /api/auth/login` — login
- `POST /api/auth/reset-password` — reset password via recovery phrase
- `POST /api/auth/change-password` — change password (authenticated)
- `GET/PATCH /api/users/@me` — profile
- `GET/POST /api/channels` — channel management
- `GET /api/channels/{id}/messages` — message history
- `POST /api/files/upload` — file upload (multipart, 2 GB limit)
- `GET /api/files/{id}` — download with HTTP Range support
- `WS /ws?token=...` — real-time messaging

## Tech Stack

- **Server**: Go, Chi router, SQLite (WAL mode), JWT auth
- **Client**: Flutter, Material 3, Provider state management
- **Audio**: just_audio + just_audio_background
- **Video**: media_kit (Linux) / video_player (Android)
- **Calls**: flutter_webrtc

## Roadmap

- [x] Core messaging (text, media, files)
- [x] Audio player (queue, repeat, shuffle, background)
- [x] Material You themes
- [x] Password recovery
- [x] Audio/video calls + screen sharing + voice rooms
- [x] Desktop-adaptive UI
- [x] Reactions
- [x] UI redesign (Discord x Telegram style)
- [ ] Cross-platform: iOS, macOS
- [ ] VPS hosting

## Known Issues

- **KDE/Wayland screen share shows two dialogs** — KDE's `xdg-desktop-portal-kde` shows two user-visible dialogs: one for `SelectSources` and one for `Start`. This is KDE-specific behaviour (GNOME only shows one dialog). Other desktop environments may be affected — if you see an unexpected extra dialog during screen sharing, this is the cause. The functionality works correctly after accepting both dialogs.

- **Screen share audio (Linux)** — Requires PulseAudio (via `libpulse` / `libpulse-simple`) for system audio loopback capture. Works on both native PulseAudio and PipeWire (via pipewire-pulse compatibility layer). Ensure PulseAudio is running.

## License

MIT
