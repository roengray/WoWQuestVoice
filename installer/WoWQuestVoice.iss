#define MyAppName "WoWQuestVoice"
#define MyAppVersion "0.10.5"
#ifndef OutputName
  #define OutputName "WoWQuestVoiceSetup-UNSIGNED-QA"
#endif

[Setup]
AppId={{7657EB53-4325-4C85-904B-4427F1ED62C1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=WoWQuestVoice
AppPublisherURL=https://wowquestvoice-collector.wowquestvoice-ko.workers.dev/
AppSupportURL=https://wowquestvoice-collector.wowquestvoice-ko.workers.dev/
LicenseFile=..\LICENSE
InfoBeforeFile=..\PRIVACY.md
DefaultDirName={localappdata}\Programs\WoWQuestVoice
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\release\installer
OutputBaseFilename={#OutputName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=WoWQuestVoiceAgent.exe
RestartApplications=no
UninstallDisplayIcon={app}\WoWQuestVoiceAgent.exe
SetupLogging=yes
VersionInfoCompany=WoWQuestVoice
VersionInfoDescription=WoWQuestVoice installer
VersionInfoProductName=WoWQuestVoice
VersionInfoProductVersion={#MyAppVersion}
VersionInfoVersion=0.10.5.0

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
Source: "..\build\dist\WoWQuestVoiceAgent\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\WoWQuestVoice\WoWQuestVoice.toc"; DestDir: "{code:GetAddonDir}"; Flags: ignoreversion
Source: "..\WoWQuestVoice\ForeverQuestIDs.lua"; DestDir: "{code:GetAddonDir}"; Flags: ignoreversion
Source: "..\WoWQuestVoice\QuestAudioData.lua"; DestDir: "{code:GetAddonDir}"; Flags: ignoreversion
Source: "..\WoWQuestVoice\WoWQuestVoice.lua"; DestDir: "{code:GetAddonDir}"; Flags: ignoreversion
Source: "..\WoWQuestVoice\QuestAutomation.lua"; DestDir: "{code:GetAddonDir}"; Flags: ignoreversion
Source: "..\WoWQuestVoice\Options.lua"; DestDir: "{code:GetAddonDir}"; Flags: ignoreversion

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "WoWQuestVoiceBackgroundAgent"; ValueData: """{app}\WoWQuestVoiceAgent.exe"""; Flags: uninsdeletevalue; Check: ShouldRegisterStartup

[Run]
Filename: "{app}\WoWQuestVoiceAgent.exe"; Parameters: "{code:GetConfigureParameters}"; Flags: runhidden waituntilterminated
Filename: "{app}\WoWQuestVoiceAgent.exe"; Flags: runhidden nowait; Check: ShouldStartLoop
Filename: "{app}\WoWQuestVoiceAgent.exe"; Parameters: "--once"; Flags: runhidden nowait; Check: ShouldRunOnce

[UninstallDelete]
Type: filesandordirs; Name: "{code:GetAddonDir}\sounds"
Type: filesandordirs; Name: "{code:GetLocalDataDir}"

[Code]
var
  AddonDirPage: TInputDirWizardPage;
  OptionsPage: TInputOptionWizardPage;

function BoolParam(const Name: String; DefaultValue: Boolean): Boolean;
var
  Value: String;
begin
  Value := Lowercase(ExpandConstant('{param:' + Name + '|}'));
  if Value = '' then
    Result := DefaultValue
  else
    Result := (Value = '1') or (Value = 'true') or (Value = 'yes');
end;

function IsGameFolder(const Path: String): Boolean;
begin
  Result := FileExists(AddBackslash(Path) + 'WowB.exe') or
            FileExists(AddBackslash(Path) + 'Wow.exe') or
            FileExists(AddBackslash(Path) + 'WowClassic.exe') or
            FileExists(AddBackslash(Path) + 'WowClassicB.exe');
end;

function GamePathFromAddonPath(const Path: String): String;
var
  CleanPath: String;
begin
  CleanPath := RemoveBackslashUnlessRoot(Path);
  Result := ExtractFileDir(ExtractFileDir(CleanPath));
end;

function IsAddonRoot(const Path: String): Boolean;
var
  CleanPath: String;
begin
  CleanPath := RemoveBackslashUnlessRoot(Path);
  Result := (CompareText(ExtractFileName(CleanPath), 'AddOns') = 0) and
            (CompareText(ExtractFileName(ExtractFileDir(CleanPath)), 'Interface') = 0);
end;

function NormalizeAddonPath(const Path: String): String;
var
  CleanPath: String;
begin
  CleanPath := RemoveBackslashUnlessRoot(Path);
  if IsGameFolder(CleanPath) then
    Result := AddBackslash(CleanPath) + 'Interface\AddOns'
  else if CompareText(ExtractFileName(CleanPath), 'WoWQuestVoice') = 0 then
    Result := ExtractFileDir(CleanPath)
  else
    Result := CleanPath;
end;

function SuggestedAddonPath(): String;
var
  Candidate, Drive, DriveLetters: String;
  I: Integer;
begin
  Candidate := ExpandConstant('{param:WOWPATH|}');
  if Candidate <> '' then begin
    Result := NormalizeAddonPath(Candidate);
    Exit;
  end;

  if RegQueryStringValue(HKLM32,
       'SOFTWARE\Blizzard Entertainment\World of Warcraft\Beta',
       'InstallPath', Candidate) and IsGameFolder(Candidate) then begin
    Result := NormalizeAddonPath(Candidate);
    Exit;
  end;
  if RegQueryStringValue(HKLM64,
       'SOFTWARE\Blizzard Entertainment\World of Warcraft\Beta',
       'InstallPath', Candidate) and IsGameFolder(Candidate) then begin
    Result := NormalizeAddonPath(Candidate);
    Exit;
  end;
  if RegQueryStringValue(HKCU,
       'Software\Blizzard Entertainment\World of Warcraft\Beta',
       'InstallPath', Candidate) and IsGameFolder(Candidate) then begin
    Result := NormalizeAddonPath(Candidate);
    Exit;
  end;

  DriveLetters := 'BCDEFGHIJKLMNOPQRSTUVWXYZA';
  for I := 1 to Length(DriveLetters) do begin
    Drive := Copy(DriveLetters, I, 1) + ':\';
    Candidate := Drive + 'GAME\World of Warcraft\_classic_beta_';
    if IsGameFolder(Candidate) then begin Result := NormalizeAddonPath(Candidate); Exit; end;
    Candidate := Drive + 'Games\World of Warcraft\_classic_beta_';
    if IsGameFolder(Candidate) then begin Result := NormalizeAddonPath(Candidate); Exit; end;
    Candidate := Drive + 'World of Warcraft\_classic_beta_';
    if IsGameFolder(Candidate) then begin Result := NormalizeAddonPath(Candidate); Exit; end;
    Candidate := Drive + 'Program Files (x86)\World of Warcraft\_classic_beta_';
    if IsGameFolder(Candidate) then begin Result := NormalizeAddonPath(Candidate); Exit; end;
    Candidate := Drive + 'Program Files\World of Warcraft\_classic_beta_';
    if IsGameFolder(Candidate) then begin Result := NormalizeAddonPath(Candidate); Exit; end;
  end;

  Result := ExpandConstant('{sd}\World of Warcraft\_classic_beta_\Interface\AddOns');
end;

procedure InitializeWizard();
begin
  AddonDirPage := CreateInputDirPage(wpSelectDir,
    'WoW 애드온 설치 폴더',
    'WoW Classic Beta의 AddOns 폴더를 확인하세요.',
    '자동으로 찾은 _classic_beta_\Interface\AddOns 폴더입니다. 찾지 못한 경우 올바른 AddOns 폴더를 선택하세요.', False, '');
  AddonDirPage.Add('');
  AddonDirPage.Values[0] := SuggestedAddonPath();

  OptionsPage := CreateInputOptionPage(AddonDirPage.ID,
    '자동 업데이트 및 데이터 수집',
    '사용할 기능을 선택하세요.',
    '음성 데이터는 첫 실행 때 약 316MB를 내려받습니다. 데이터 수집은 선택 사항입니다.',
    False, False);
  OptionsPage.Add('새 음성 파일 자동 업데이트');
  OptionsPage.Add('Windows 로그인 때 업데이터 자동 시작');
  OptionsPage.Add('익명 퀘스트 문장 수집에 동의');
  OptionsPage.Values[0] := BoolParam('UPDATES', True);
  OptionsPage.Values[1] := BoolParam('AUTOSTART', True);
  OptionsPage.Values[2] := BoolParam('COLLECT', False);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  GamePath: String;
begin
  Result := True;
  if CurPageID = AddonDirPage.ID then begin
    AddonDirPage.Values[0] := NormalizeAddonPath(AddonDirPage.Values[0]);
    GamePath := GamePathFromAddonPath(AddonDirPage.Values[0]);
    if ((not IsAddonRoot(AddonDirPage.Values[0])) or
        (not IsGameFolder(GamePath))) and
       (not BoolParam('ALLOWFAKE', False)) then begin
      MsgBox('_classic_beta_\Interface\AddOns 폴더를 선택하세요.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function GetAddonDir(Param: String): String;
begin
  Result := AddBackslash(AddonDirPage.Values[0]) + 'WoWQuestVoice';
end;

function GetGameDir(): String;
begin
  Result := GamePathFromAddonPath(AddonDirPage.Values[0]);
end;

function GetLocalDataDir(Param: String): String;
begin
  Result := ExpandConstant('{param:LOCALDATAPATH|}');
  if Result = '' then
    Result := ExpandConstant('{localappdata}\WoWQuestVoice');
end;

function GetConfigureParameters(Param: String): String;
begin
  Result := '--configure --game-path "' + GetGameDir() + '"';
  if OptionsPage.Values[0] then
    Result := Result + ' --enable-updates'
  else
    Result := Result + ' --disable-updates';
  if OptionsPage.Values[2] then
    Result := Result + ' --enable-upload'
  else
    Result := Result + ' --disable-upload';
end;

function AgentNeeded(): Boolean;
begin
  Result := OptionsPage.Values[0] or OptionsPage.Values[2];
end;

function DownloadSuppressed(): Boolean;
begin
  Result := BoolParam('NODOWNLOAD', False);
end;

function ShouldRegisterStartup(): Boolean;
begin
  Result := AgentNeeded() and OptionsPage.Values[1];
end;

function ShouldStartLoop(): Boolean;
begin
  Result := AgentNeeded() and OptionsPage.Values[1] and (not DownloadSuppressed());
end;

function ShouldRunOnce(): Boolean;
begin
  Result := AgentNeeded() and (not OptionsPage.Values[1]) and (not DownloadSuppressed());
end;
