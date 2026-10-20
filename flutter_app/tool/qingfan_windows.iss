; Qingfan V2 Windows — unsigned candidate installer
#define AppName "Qingfan"
#define AppVersion "2.0.0-dev2"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Qingfan
DefaultDirName={autopf}\Qingfan
DefaultGroupName=Qingfan
OutputDir=..\dist
OutputBaseFilename=qingfan-v2-windows-x64-installer-unsigned
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
UninstallDisplayName=青番
WizardStyle=modern

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\青番"; Filename: "{app}\qingfan.exe"
Name: "{autodesktop}\青番"; Filename: "{app}\qingfan.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "其他选项："; Flags: unchecked

[Run]
Filename: "{app}\qingfan.exe"; Description: "启动青番"; Flags: postinstall nowait skipifsilent
