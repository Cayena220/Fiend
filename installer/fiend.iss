; Per-user installer for Fiend. It needs no admin rights: the app goes to
; %LOCALAPPDATA%\Programs\Fiend and the uninstall entry to HKCU.
; scripts/build.ps1 compiles it after the release build:
;   ISCC /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutputDir=<web\downloads> installer\fiend.iss
; The wizard artwork and app_icon.ico come from scripts/make-icon.mjs.

#ifndef AppVersion
  #error Pass the version, for example /DAppVersion=1.0.0
#endif
#ifndef SourceDir
  #define SourceDir "..\app\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\web\downloads"
#endif

[Setup]
; Keep AppId fixed forever: it is how upgrades and the uninstaller find this app.
AppId={{40A48CD8-6355-4EB6-848A-FC6E92489260}
AppName=Fiend
AppVersion={#AppVersion}
AppVerName=Fiend {#AppVersion}
AppPublisher=Fiend
AppPublisherURL=https://fiend-delta.vercel.app
AppSupportURL=https://fiend-delta.vercel.app
AppUpdatesURL=https://fiend-delta.vercel.app/#download
VersionInfoVersion={#AppVersion}
VersionInfoDescription=Fiend Setup
PrivilegesRequired=lowest
DefaultDirName={userpf}\Fiend
DisableProgramGroupPage=yes
DisableReadyPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Fiend.exe holds this mutex while it runs, so Setup and Uninstall ask the user to close it first.
AppMutex=FiendAppMutex
OutputDir={#OutputDir}
OutputBaseFilename=Fiend-{#AppVersion}-setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Fiend.exe
UninstallDisplayName=Fiend
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern dark
WizardImageFile=wizard-100.png,wizard-125.png,wizard-150.png,wizard-200.png
WizardSmallImageFile=wizard-small-100.png,wizard-small-125.png,wizard-small-150.png,wizard-small-200.png

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
; The Ready page is skipped, so the tasks page is the one that starts the install.
SelectTasksLabel2=Select the additional tasks you would like Setup to perform while installing [name], then click Install.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Flutter assets are replaced wholesale on upgrade so no stale files linger.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Fiend"; Filename: "{app}\Fiend.exe"; Comment: "Clean caches, map your disks and hunt what hides on your PC"
Name: "{autodesktop}\Fiend"; Filename: "{app}\Fiend.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Fiend.exe"; Description: "{cm:LaunchProgram,Fiend}"; Flags: nowait postinstall skipifsilent

[Code]
// Settings, scan state, signatures and the quarantine vault live in %APPDATA%\Fiend.
// Uninstall keeps them unless the user ticks the box (or passes /DELETEDATA when silent).
var
  DeleteData: Boolean;

function DataDir(): String;
begin
  Result := ExpandConstant('{userappdata}\Fiend');
end;

function HasSwitch(const Name: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Name) = 0 then
      Result := True;
end;

// Shown after Uninstall's own "Are you sure?" prompt and its check that Fiend isn't
// running, just before files are removed. Returns True if the box is ticked.
function AskAboutData(): Boolean;
var
  Form: TSetupForm;
  Intro, Path: TNewStaticText;
  Box: TNewCheckBox;
  OkButton: TNewButton;
  Margin, Width, Y: Integer;
begin
  Margin := ScaleX(16);
  Form := CreateCustomForm(ScaleX(400), ScaleY(200), False, True);
  try
    Form.Caption := 'Uninstall Fiend';
    Width := Form.ClientWidth - 2 * Margin;

    Intro := TNewStaticText.Create(Form);
    Intro.Parent := Form;
    Intro.WordWrap := True;
    Intro.Left := Margin;
    Intro.Top := ScaleY(16);
    Intro.Width := Width;
    Intro.Caption := 'Fiend keeps your settings, scan history and quarantined files in this folder. ' +
      'They stay on this PC unless you choose to delete them, so a reinstall picks up where you left off.';
    Y := Intro.Top + Intro.Height + ScaleY(8);

    Path := TNewStaticText.Create(Form);
    Path.Parent := Form;
    Path.Left := Margin;
    Path.Top := Y;
    Path.Width := Width;
    Path.Caption := DataDir();
    Path.Font.Style := [fsBold];
    Y := Path.Top + Path.Height + ScaleY(16);

    Box := TNewCheckBox.Create(Form);
    Box.Parent := Form;
    Box.Left := Margin;
    Box.Top := Y;
    Box.Width := Width;
    Box.Height := ScaleY(20);
    Box.Caption := '&Delete my Fiend data too (quarantined files are removed for good)';
    Y := Box.Top + Box.Height + ScaleY(20);

    OkButton := TNewButton.Create(Form);
    OkButton.Parent := Form;
    OkButton.Caption := '&Continue';
    OkButton.ModalResult := mrOk;
    OkButton.Default := True;
    OkButton.Cancel := True;
    OkButton.Width := Form.CalculateButtonWidth([OkButton.Caption]);
    OkButton.Height := ScaleY(23);
    OkButton.Left := Form.ClientWidth - Margin - OkButton.Width;
    OkButton.Top := Y;
    Form.ClientHeight := Y + OkButton.Height + ScaleY(14);

    Form.ActiveControl := OkButton;
    // Closing the window counts as "keep my data".
    Result := (Form.ShowModal() = mrOk) and Box.Checked;
  finally
    Form.Free();
  end;
end;

// With no Ready page, Next on the tasks page starts the install, so say so.
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectTasks then
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if UninstallSilent() then
    DeleteData := HasSwitch('/DELETEDATA');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  case CurUninstallStep of
    usUninstall:
      if not UninstallSilent() and DirExists(DataDir()) then
        DeleteData := AskAboutData();
    usPostUninstall:
      if DeleteData then
        DelTree(DataDir(), True, True, True);
  end;
end;
