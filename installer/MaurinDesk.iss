#ifndef AppVersion
  #define AppVersion "0.6.8"
#endif

[Setup]
AppId={{8F3B9C1A-4D2E-4A7B-9E15-3C6A2D8E4F10}
AppName=MaurinDesk
AppVersion={#AppVersion}
AppVerName=MaurinDesk {#AppVersion}
AppPublisher=MaurinSoft
AppPublisherURL=https://maurinsoft.com.br/MaurinDesk
AppSupportURL=https://maurinsoft.com.br/MaurinDesk
DefaultDirName={localappdata}\Programs\MaurinSoft\MaurinDesk
DefaultGroupName=MaurinDesk
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\desktop\MaurinDesk.ico
UninstallDisplayIcon={app}\MaurinDesk.exe
OutputDir=..\bin
OutputBaseFilename=MaurinDesk-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "autostart"; Description: "Iniciar com o Windows (minimizado na bandeja)"; GroupDescription: "Opções adicionais:"; Flags: checkedonce
Name: "desktopicon"; Description: "Criar ícone na Área de Trabalho"; GroupDescription: "Opções adicionais:"

[Files]
Source: "..\bin\MaurinDesk.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\libssl-3-x64.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\libcrypto-3-x64.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\MaurinDesk.ini"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist

[Icons]
Name: "{autoprograms}\MaurinDesk"; Filename: "{app}\MaurinDesk.exe"; Comment: "MaurinDesk — acesso remoto assistido"
Name: "{autodesktop}\MaurinDesk"; Filename: "{app}\MaurinDesk.exe"; Tasks: desktopicon; Comment: "MaurinDesk — acesso remoto assistido"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "MaurinDesk"; ValueData: """{app}\MaurinDesk.exe"" --minimized"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\MaurinDesk.exe"; Description: "Executar MaurinDesk agora"; Flags: nowait postinstall skipifsilent
