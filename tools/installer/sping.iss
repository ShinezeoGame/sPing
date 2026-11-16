; Installateur Windows de sPing (Inno Setup 6).
;
; Compilé par .github/workflows/build.yml une fois l'application assemblée dans
; build\windows\x64\runner\Release :
;
;     ISCC.exe /DAppVersion=1.0.12 tools\installer\sping.iss
;
; L'installation se fait dans le profil de l'utilisateur : aucun droit d'administrateur requis.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{7B2D4C19-5E8F-4A36-9C01-D84F2E6B7A58}
AppName=sPing
AppVersion={#AppVersion}
AppPublisher=ShinezeoGame
AppPublisherURL=https://github.com/ShinezeoGame/sPing
DefaultDirName={autopf}\sPing
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..
OutputBaseFilename=sping-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sping.exe
UninstallDisplayName=sPing
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Une mise à jour ferme sPing avant de remplacer les fichiers.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\sPing"; Filename: "{app}\sping.exe"
Name: "{autodesktop}\sPing"; Filename: "{app}\sping.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sping.exe"; Description: "{cm:LaunchProgram,sPing}"; Flags: nowait postinstall skipifsilent

[Registry]
; « Démarrer avec Windows » (réglage de sPing) : retiré à la désinstallation.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "sPing"; Flags: uninsdeletevalue dontcreatekey
