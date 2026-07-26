; Inno Setup script for WeatherFast (Windows).
;
; Per-user install (no administrator rights) into %LocalAppData%, so the in-app
; updater can download and run a new installer without elevation - mirroring the
; per-user model QuickMail uses via Velopack. The version is passed by the CI
; build with /DMyAppVersion=x.y.z; it defaults to 0.0.0 for local test compiles.
;
; Build locally (after `python build.py` in ../windows):
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=1.1 weatherfast.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppName "WeatherFast"
#define MyAppPublisher "Kelly Ford"
#define MyAppExeName "WeatherFast.exe"
#define MyAppURL "https://github.com/kellylford/WeatherFast"

[Setup]
; Stable AppId so upgrades replace the prior install (never change this GUID).
AppId={{7C2F1B84-3A6E-4E2B-9C1D-9E7A4F0B21A5}
; The running app holds this named mutex; lets the installer detect and wait
; for it to close before replacing the (in-app auto-update) executable.
AppMutex=WeatherFastRunning
CloseApplications=yes
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\WeatherFast
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=WeatherFast-{#MyAppVersion}-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; The PyInstaller one-dir build output (produced by ../windows/build.py): the
; executable plus its _internal support folder.
Source: "..\windows\dist\WeatherFast\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autostartmenu}\WeatherFast"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\WeatherFast"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch WeatherFast"; Flags: nowait postinstall skipifsilent

[Code]
// Force-close any WeatherFast process still holding the installed executable.
// (Comments here use // rather than braces: Inno's brace comments do not nest,
// so an {app}-style constant inside one would terminate it early.)
//
// AppMutex and CloseApplications are not sufficient when upgrading from a 3.0.x
// one-file build. Those ran a bootloader parent plus a Python child, and only
// the child created WeatherFastRunning - so once it exited the mutex was gone
// even though the parent was still alive holding the .exe open, parked on the
// bootloader's "Failed to remove temporary directory" dialog. Restart Manager
// cannot shift that either: a process whose message loop has already ended does
// not act on the WM_CLOSE that CloseApplications sends. The result was setup
// failing with "DeleteFile failed; code 5. Access is denied."
//
// Killing it is safe here: in that state the application has finished its work
// and is only displaying a shutdown warning. A genuinely running instance is
// still caught earlier by AppMutex, which prompts the user first.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';  // never block the install - a lock still surfaces as a file error
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM WeatherFast.exe', '',
       SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // 128 = "no such process", the normal case. Give Windows a moment either way
  // so the handle is released before the file copy starts.
  Sleep(500);
end;
