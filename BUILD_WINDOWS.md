# Privchat — Windows Build

## Requirements
- Windows 10+ (x64)
- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (3.44.2)
- [Visual Studio 2022](https://visualstudio.microsoft.com/) with "Desktop development with C++"
- [Git](https://git-scm.com/)
- [Inno Setup](https://jrsoftware.org/isinfo.php) (optional, for installer)

## Build

```powershell
git clone https://github.com/ilertnost/Barricade.git
cd Barricade
git checkout Windows
cd client

flutter pub get
flutter build windows --release
```

Output: `build\windows\x64\release\bundle\privchat.exe`

## Installer

Open `installer.iss` (in repo root) with Inno Setup and compile.

## Notes
- Screen share audio uses Windows WASAPI loopback (built into flutter_webrtc).
- Firebase Cloud Messaging not available on desktop — push notifications are Android-only.
- Config file at `client\lib\config.dart` — change server IP before building for your environment.
