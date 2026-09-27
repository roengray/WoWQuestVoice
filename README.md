# WoWQuestVoice

WoWQuestVoice는 World of Warcraft Classic Beta의 한국어 퀘스트 본문을 게임 안에서 음성으로 재생하는 애드온입니다. 퀘스트 창의 재생·정지 버튼, 재생 중 음악과 효과음 볼륨 조정, 퀘스트 자동 수락·보고 선택 기능을 제공합니다.

Windows 설치 프로그램은 애드온과 백그라운드 업데이터만 포함합니다. 약 316MB의 음성 데이터는 첫 실행 뒤 두 묶음으로 내려받고, 이후에는 바뀐 묶음만 업데이트합니다.

## 설치

1. [공식 다운로드 페이지](https://wowquestvoice-collector.wowquestvoice-ko.workers.dev/)에서 설치 프로그램을 받습니다.
2. 설치 프로그램에서 `_classic_beta_` 폴더를 선택합니다.
3. 자동 업데이트와 익명 퀘스트 문장 수집 여부를 선택합니다. 문장 수집은 기본적으로 꺼져 있습니다.
4. 게임에서 `/reload`를 실행하거나 다시 접속합니다.

프로그램 제거는 Windows의 **설치된 앱**에서 WoWQuestVoice를 선택하면 됩니다.

## 개인정보

수집 항목과 끄는 방법은 [개인정보 처리 안내](PRIVACY.md)에 설명되어 있습니다.

## 개발 빌드

Windows와 Python 3.12가 필요합니다.

```powershell
python -m pip install -r requirements-build.txt
Copy-Item collector_public_config.example.json collector_public_config.json
.\build_installer.ps1
```

생성된 `release/installer/WoWQuestVoiceSetup-UNSIGNED-QA.exe`는 서명 전 검사용 파일입니다. 일반 사용자 배포에는 서명된 릴리스만 사용합니다.

## Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io/), certificate by [SignPath Foundation](https://signpath.org/). 역할, 검토와 승인 절차는 [Code signing policy](CODE_SIGNING_POLICY.md)에 설명되어 있습니다.

## 라이선스

소스 코드는 [MIT License](LICENSE)로 배포됩니다. World of Warcraft는 Blizzard Entertainment의 상표이며 이 프로젝트는 Blizzard Entertainment와 관련이 없습니다.
