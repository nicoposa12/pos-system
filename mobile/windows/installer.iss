; Script generated for TindaKo POS
; Single-Click Windows Installer for Store Owners and Cashiers

#define MyAppName "TindaKo"
#ifndef MyAppVersion
#define MyAppVersion "1.0.6"
#endif
#define MyAppPublisher "TindaKo"
#define MyAppURL "https://pos-system-1-y58u.onrender.com"
#define MyAppExeName "tindako.exe"

[Setup]
; AppId uniquely identifies TindaKo POS on the machine for upgrades/uninstall
AppId={{9F57AC86-C3BD-4B2E-BE6C-3C61D36B429A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
DisableProgramGroupPage=yes
; Allow installing without Administrator privileges for simple store PCs
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline dialog
CloseApplications=force
RestartApplications=no
OutputDir=..\build\windows\installer
OutputBaseFilename=TindaKo-Setup-v{#MyAppVersion}
SetupIconFile=C:\Users\basco\Devs\pos_system\mobile\windows\runner\resources\app_icon.ico
SolidCompression=yes
Compression=lzma2/ultra64
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall

