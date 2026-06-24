; Privchat Windows Installer (Inno Setup)
; Build Windows release first: flutter build windows --release
; Then compile this script with Inno Setup.

#define MyAppName "Privchat"
#define MyAppVersion "1.0.0.6002"
#define MyAppPublisher "Privchat"
#define MyAppURL "https://privchat.app"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=privchat-setup-6002
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\privchat.exe

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "build\windows\x64\release\bundle\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\privchat.exe"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\privchat.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\privchat.exe"; Description: "Launch Privchat"; Flags: postinstall nowait skipifsilent
