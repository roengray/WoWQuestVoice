#define MyAppName "WoWQuestVoice"
#define MyAppVersion "0.10.4"
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
VersionInfoVersion=0.10.4.0

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
  GameDirPage: TInputDirWizardPage;
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

function SuggestedGamePath(): String;
var
  Candidate: String;
begin
  Candidate := ExpandConstant('{param:WOWPATH|}');
  if Candidate <> '' then begin
    Result := Candidate;
    Exit;
  end;
  Candidate := ExpandConstant('{pf32}\World of Warcraft\_classic_beta_');
  if DirExists(Candidate) then begin
    Result := Candidate;
    Exit;
  end;
  Candidate := ExpandConstant('{pf}\World of Warcraft\_classic_beta_');
  if DirExists(Candidate) then begin
    Result := Candidate;
    Exit;
  end;
  Result := ExpandConstant('{sd}\World of Warcraft\_classic_beta_');
end;

procedure InitializeWizard();
begin
  GameDirPage := CreateInputDirPage(wpSelectDir,
    '월드 오브 워크래프트 폴더',
    'WoW Classic Beta 설치 폴더를 선택하세요.',
    'WowB.exe가 들어 있는 _classic_beta_ 폴더를 선택하세요.', False, '');
  GameDirPage.Add('');
  GameDirPage.Values[0] := SuggestedGamePath();

  OptionsPage := CreateInputOptionPage(GameDirPage.ID,
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

function IsGameFolder(const Path: String): Boolean;
begin
  Result := FileExists(AddBackslash(Path) + 'WowB.exe') or
            FileExists(AddBackslash(Path) + 'Wow.exe') or
            FileExists(AddBackslash(Path) + 'WowClassic.exe') or
            FileExists(AddBackslash(Path) + 'WowClassicB.exe');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = GameDirPage.ID) and
     (not IsGameFolder(GameDirPage.Values[0])) and
     (not BoolParam('ALLOWFAKE', False)) then begin
    MsgBox('선택한 폴더에서 WoW 실행 파일을 찾지 못했습니다.', mbError, MB_OK);
    Result := False;
  end;
end;

function GetAddonDir(Param: String): String;
begin
  Result := AddBackslash(GameDirPage.Values[0]) + 'Interface\AddOns\WoWQuestVoice';
end;

function GetLocalDataDir(Param: String): String;
begin
  Result := ExpandConstant('{param:LOCALDATAPATH|}');
  if Result = '' then
    Result := ExpandConstant('{localappdata}\WoWQuestVoice');
end;

function GetConfigureParameters(Param: String): String;
begin
  Result := '--configure --game-path "' + GameDirPage.Values[0] + '"';
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
