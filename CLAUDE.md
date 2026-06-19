# StarLink 개발 가이드 (CLAUDE.md)

이 문서는 StarLink 프로젝트의 빌드, 테스트 및 맥북 내부 가상 테스트 하네스 구성 가이드를 포함합니다.

## 프로젝트 개요
StarLink는 Gemini 3.5 Live Translate API를 통해 에어팟(AirPods), 갤럭시 버즈(Galaxy Buds) 등 무선 이어폰 및 블루투스 오디오 기기, MFi 보청기 사용자를 위한 실시간 한국어 동시 통번역 음성 스트리밍을 제공하는 iOS 애플리케이션 및 백엔드 에이전트 시스템입니다.

## 🛠 빌드 및 실행 명령어

### 1. 로컬 보안 설정 (빌드 전 필수)
오픈소스 공개를 위해 실사용 자격 증명은 Git 추적에서 제외되어 있습니다. 아래 명령어로 보안 설정 파일을 복제한 뒤 내용을 채워 넣으십시오.
```bash
cp StarLink/Secrets.plist.example StarLink/Secrets.plist
# 그 후 Secrets.plist의 LIVEKIT_URL 및 LIVEKIT_TOKEN 등을 본인 계정에 맞게 작성합니다.
```

### 2. Xcode 프로젝트 파일 생성
```bash
# XcodeGen을 통한 프로젝트 재생성
xcodegen generate
```

### 3. 백엔드 에이전트 및 토큰 서버 실행

#### 번역 에이전트 실행
```bash
cd backend
source venv/bin/activate
python agent.py dev
```

#### 토큰 서버 실행
```bash
cd backend
source venv/bin/activate
python server.py
```

### 4. 💻 맥북 내부 원클릭 시뮬레이터 실행 (추천 ⭐️)
Xcode GUI 프로그램을 켜거나 실기기 아이폰을 준비할 필요 없이, 맥북 터미널에서 아래 단 한 줄의 명령어로 iOS 시뮬레이터에 최신 빌드를 배포하고 자동 실행시킬 수 있습니다.
```bash
# 실행 권한 부여 후 스크립트 가동 (자동 컴파일 -> 시뮬레이터 기동 -> 앱 실행)
./run_simulator.sh
```

---

## 🎧 맥북 내부 완전 무소음 테스트 환경 구축 팁 (선택)
스피커로 새어 나오는 유튜브 영어 소리가 마이크로 잘 안 들어가거나 웅웅거릴 때, 맥북 내부 오디오 출력을 가상으로 마이크 입력에 다이렉트 맵핑하는 방법입니다.

1. **BlackHole (가상 오디오 드라이버) 설치**:
   ```bash
   brew install blackhole-2ch
   ```
2. **다중 출력 기기 생성**:
   * 맥북의 `오디오 MIDI 설정` 앱을 켭니다.
   * 좌측 하단 `+` 버튼을 누르고 `다중 출력 기기 생성`을 선택합니다.
   * `내장 스피커`와 `BlackHole 2ch`를 둘 다 체크합니다.
3. **오디오 출력/입력 설정**:
   * 맥북 상단 바 오디오 출력 대상을 방금 만든 **다중 출력 기기**로 변경합니다. (유튜브 소리가 스피커로도 나고 가상 드라이버로도 동시 흐르게 됨)
   * iOS 시뮬레이터 상단 메뉴 `I/O` -> `Audio Input` -> `BlackHole 2ch`를 선택합니다.
4. **결과**: 유튜브 영어 소리가 100% 디지털 무손실 음질로 시뮬레이터 앱 마이크로 직접 유입되어 완벽하게 번역되는 쾌적한 테스트 환경이 완성됩니다.

---

## 📋 핵심 아키텍처 및 구현 규칙

### 1. 오디오 세션 제어 원칙
* **LiveKit 자동 구성 권장 (`isAutomaticConfigurationEnabled = true`)**: 비동기 오디오 스레드 락 및 프리징 데드락 방지를 위해 오디오 세션 수명주기 관리는 LiveKit SDK에 완전히 위임합니다.
* **스피커 출력 경로 제어**: `AVAudioSession` 직접 조작 대신 LiveKit SDK의 공식 API인 `LiveKit.AudioManager.shared.isSpeakerOutputPreferred`를 사용하여 스피커/블루투스 출력 경로를 통제합니다.
* **마이크 음소거 최소화**: WebRTC 오디오 디바이스 락 방지를 위해 마이크 트랙의 물리적인 mute/unmute를 지양하고, 대신 에코 및 백채널 가로채기 방지를 위해 백엔드 `AgentSession`에서 인터럽션 설정을 비활성화(`"interruption": {"enabled": False}`)합니다.

### 2. Gemini Live API 모델 규칙 (★절대 준수 및 박제★)
* **공식 모델명 강제 고정**: 백엔드 `agent.py` 및 모델 테스트 시 반드시 **`gemini-3.5-live-translate-preview`** 모델명을 사용해야 합니다.
  > [!IMPORTANT]
  > 현재 환경의 Google API Key 자격 증명으로는 오직 `gemini-3.5-live-translate-preview` 모델만 WebSocket 연결이 가능합니다. 
  > 임의로 `gemini-2.0-flash-exp` 혹은 `gemini-2.5-flash` 등의 하위 표준 모델명을 사용할 경우 `1008 Policy Violation (Not found / Not supported)` 오류가 발생하며 연결이 거부됩니다. 어떠한 경우에도 모델명을 임의 변경하지 마십시오.
* **정보 제한 시 유저 요청**: API 스펙이나 파라미터에 의문이 생길 경우, 임의로 다른 하위 모델명으로 변경하지 말고 **사용자에게 공식 리소스 조사를 명확하게 요청**하십시오.

