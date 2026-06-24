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
- FCM push notifications
- Russian + English interface
- Android (primary target)

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
- [x] Reactions
- [x] UI redesign (Discord x Telegram style)
- [ ] Screen share viewing (Discord-style picture-in-picture)
- [ ] Chat settings (per-channel)

## License

MIT
