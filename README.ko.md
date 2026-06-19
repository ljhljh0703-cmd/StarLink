<div align="center">

# 🎙️ StarLink

**무선 이어폰·블루투스 오디오를 위한 실시간 동시통역**

주변의 영어·일본어·중국어 음성을 한국어로 통역해 — 에어팟, 갤럭시 버즈, 블루투스 이어버드, MFi 보청기로 1초 미만 지연으로 직접 스트리밍합니다.

[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org/)
[![Gemini 3.5 Live](https://img.shields.io/badge/Gemini-3.5%20Live-4285F4?logo=google&logoColor=white)](https://ai.google.dev/)
[![LiveKit WebRTC](https://img.shields.io/badge/LiveKit-2.0-purple?logo=livekit&logoColor=white)](https://livekit.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[English](README.md) &nbsp;|&nbsp; **🌐 한국어**

</div>

---

## 📖 개요

**StarLink**는 무선 오디오 기기를 통한 **핸즈프리 실시간 동시통역**을 위해 설계된 iOS 애플리케이션 + 백엔드 에이전트 시스템입니다.

아이폰을 에어팟·갤럭시 버즈 같은 블루투스 이어폰 또는 MFi(Made for iPhone) 보청기와 페어링하면, 주변의 외국어 음성을 포착해 저지연 WebRTC 연결로 **Gemini 3.5 Live Translate** 기반 백엔드 에이전트에 스트리밍하고, 자연스러운 한국어 음성을 사용자의 귀로 직접 전달합니다. 동시에 입력 언어를 자동 감지해 실시간 동기화 자막을 화면에 표시합니다.

---

## 🎬 데모 & 포트폴리오

> 📹 **데모 영상** 과 🔗 **인터랙티브 포트폴리오 페이지** — _준비 중._
<!-- DEMO_URL: replace with the demo video link when ready -->
<!-- PORTFOLIO_URL: replace with the portfolio page link when ready -->

---

## 🎧 지원 오디오 기기

StarLink는 **모든 무선 오디오 출력 장치**에서 동작합니다 — 에어팟, 갤럭시 버즈, 일반 블루투스 이어버드, MFi 보청기를 모두 동일하게 처리합니다. **기기별 별도 설정이 필요 없으며**, 연결된 무선 기기로 통역 음성이 자동 라우팅됩니다.

> **비(非)보청기 사용자 참고:** 무선 기기가 연결돼 있는 동안에는 아이폰 내장 스피커로의 강제 출력이 의도적으로 비활성화됩니다(MFi 기기 라우팅 보호 장치). 통역을 폰 스피커로 듣고 싶다면 먼저 무선 기기 연결을 해제하세요.

---

## ⚡ 해결한 핵심 엔지니어링 과제 (포트폴리오 하이라이트)

이 프로젝트는 iOS의 여러 복잡한 실시간 오디오 엔지니어링 및 WebRTC 과제를 다룹니다.

### 1. 블루투스 & MFi 오디오 라우팅 제어

* **과제**: LiveKit의 자동 오디오 구성이 iOS `AVAudioSession` 카테고리를 재설정해, 연결된 블루투스 이어폰·MFi 보청기 대신 아이폰 내장 리시버(통화용 스피커)로 오디오가 라우팅되는 문제가 발생합니다.
* **해결**: 오디오 세션 수명주기 관리를 LiveKit SDK에 위임하되, 출력 경로 제어는 직접 조작(`AVAudioSession`) 대신 LiveKit의 공식 API(`AudioManager.shared.isSpeakerOutputPreferred`)로 통제. 보청기 연결 시 스피커 우선을 비활성(`false`)으로 강제하고, 블루투스 정착(settle) 지연을 두어 `AUIOClient_StartIO` 데드락을 회피합니다.

### 2. 음향 피드백 루프 방지

* **과제**: 이어폰으로 재생되는 통역 음성이 아이폰 마이크로 다시 새어 들어가면, AI 에이전트가 자신의 통역 음성을 듣고 재통역하는 무한 에코 루프가 발생할 수 있습니다.
* **해결**: WebRTC 오디오 디바이스 락을 피하기 위해 마이크 트랙의 물리적 mute/unmute를 지양하고, 대신 백엔드 `AgentSession`에서 인터럽션 설정을 비활성화(`"interruption": {"enabled": False}`)해 에코·백채널 가로채기를 차단합니다.

### 3. 음성-자막 모달리티 동기화

* **과제**: Gemini Live 음성-대-음성 모델은 원시 오디오 패킷을 생성하며, 기본 상태에서는 대응하는 전사(transcription) 스트림을 보내지 않아 화면 자막이 로딩 상태에 멈춥니다.
* **해결**: Gemini 세션 초기화 시 입력·출력 스트림 양쪽에 전사 설정을 주입해 모델이 전사 토큰을 동시에 방출하도록 강제. 이를 포착·파싱해 오디오 재생과 동기화하여 SwiftUI 뷰로 전달합니다.

### 4. 무지연 입력 언어 감지

* **과제**: 다국어 대화를 통역하려면 원문 언어(영어·일본어·중국어 등)를 사용자에게 표시해야 하는데, 외부 번역 API로 언어를 감지하면 허용 불가한 네트워크 지연이 생깁니다.
* **해결**: 백엔드에 0ms 지연의 경량 유니코드 블록 분석기(`detect_language`)를 구현. 스트리밍 세그먼트의 문자 집합(한글·히라가나/가타카나·CJK 한자·라틴)을 매핑해 언어 코드를 패키징하고, LiveKit 데이터 채널로 전송해 실시간 언어 배지(`[영어]`, `[일본어]` 등)를 렌더링합니다.

---

## 🏗️ 아키텍처 & 데이터 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                        iPhone (StarLink App)                    │
│                                                                 │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────────┐  │
│  │ Mic      │───▶│ LiveKit SDK  │◀──▶│ Audio Session Manager │  │
│  │ (Ambient)│    │ (Room Client)│    │ (MFi/Bluetooth Route) │  │
│  └──────────┘    └──────┬───────┘    └──────────┬────────────┘  │
│                         │                       │               │
│                         │ WebRTC (Audio Track)  │ Bluetooth     │
│                         ▼                       ▼               │
│                  ┌──────────────┐        ┌──────────────┐       │
│                  │ Caption View │        │ AirPods /    │       │
│                  │ (SwiftUI UI) │        │ Earphones    │       │
│                  └──────────────┘        └──────────────┘       │
└─────────────────────┬───────────────────────────────────────────┘
                      │ WebRTC (양방향 오디오 & 데이터)
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LiveKit Cloud / Server                       │
│              (저지연 미디어 라우팅 엔진)                          │
└─────────────────────┬───────────────────────────────────────────┘
                      │ WebRTC (오디오 & 데이터 스트림)
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Backend Agent (Python)                        │
│  ┌─────────────────┐    ┌──────────────────────────────────┐    │
│  │ livekit-agents   │───▶│ Gemini 3.5 Live Translate       │    │
│  │ (Room Subscriber)│◀───│ (Audio-to-Audio / EN·JA·ZH→KO)   │    │
│  └─────────────────┘    └──────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

1. **오디오 캡처**: 아이폰 마이크가 주변 외국어 음성을 포착합니다.
2. **업링크 스트리밍**: LiveKit SDK가 로컬 오디오 트랙을 룸에 publish합니다.
3. **AI 통역**: Python 에이전트가 오디오 트랙을 수신해 Gemini 3.5 Live로 전달, 한국어로 통역합니다.
4. **자막 전달**: 에이전트가 원문 언어를 파싱해 전사 데이터를 `caption` 토픽의 LiveKit 데이터 채널로 publish합니다.
5. **다운링크 재생**: iOS 클라이언트가 통역된 오디오 트랙을 수신하고, 커스텀 오디오 세션 관리자가 이 스트림을 연결된 에어팟/이어폰으로 직접 라우팅합니다.
6. **UI 렌더링**: SwiftUI가 JSON 페이로드를 디코드해, 감지된 언어 배지(예: `[영어]`, `[일본어]`)와 함께 자막을 렌더링합니다.

---

## 📂 프로젝트 구조

```
StarLink/
├── project.yml              # XcodeGen 프로젝트 명세
├── README.md                # 영문 문서
├── README.ko.md             # 이 문서 (한국어)
├── LICENSE                  # MIT 오픈소스 라이선스
├── .gitignore               # Git 제외 규칙
├── StarLink/                # iOS 앱 소스
│   ├── Info.plist           # 앱 구성 & 권한
│   ├── Config/              # 앱 설정 (AppConfig.swift)
│   ├── Secrets.plist.example # 자격증명 템플릿
│   ├── Secrets.plist        # 로컬 비밀 키 (git-ignored)
│   ├── Managers/            # 오디오 세션 & LiveKit 관리자
│   ├── Models/              # 데이터 모델 (CaptionEntry)
│   └── Views/               # SwiftUI 뷰 (CaptionScrollView, StatusBar)
└── backend/                 # Python 백엔드
    ├── agent.py             # 통역 에이전트 (Gemini Live)
    ├── server.py            # 토큰 서버 (동적 토큰 발급)
    ├── generate_token.py    # 로컬 토큰 생성 유틸
    ├── requirements.txt     # Python 의존성
    ├── .env.example         # 환경변수 템플릿
    └── .env                 # 로컬 자격증명 (git-ignored)
```

---

## ⚙️ 설정 & 설치

### 1. 사전 요구사항

* **Xcode 16.0+** (iOS 17 SDK)
* **XcodeGen** (`brew install xcodegen`)
* **Python 3.11+**
* **LiveKit Cloud 계정** ([cloud.livekit.io](https://cloud.livekit.io))
* **Google Gemini API Key** ([aistudio.google.com](https://aistudio.google.com/apikey))
* **실기기 iOS 디바이스** (에어팟/블루투스 오디오 라우팅은 시뮬레이터로 테스트 불가)

---

### 2. 자격증명 설정

#### iOS 클라이언트 설정 (정적/사전구성 모드)

1. 자격증명 템플릿 복제:
   ```bash
   cp StarLink/Secrets.plist.example StarLink/Secrets.plist
   ```
2. `StarLink/Secrets.plist`를 열어 LiveKit WebSocket URL 입력:
   * `LIVEKIT_URL`: `wss://your-project.livekit.cloud`
   * `LIVEKIT_TOKEN`: (선택) 개발용 정적 JWT 토큰.
   * `TOKEN_SERVER_URL`: (선택) 배포한 토큰 서버 URL (예: `https://your-backend.com/api/token`). 지정 시 앱이 시작할 때 단기 토큰을 동적으로 가져옵니다.
3. Xcode 프로젝트 생성:
   ```bash
   xcodegen generate
   ```
4. `StarLink.xcodeproj`를 열고 Target → Signing & Capabilities에서 **Development Team**을 설정한 뒤 실기기에서 빌드/실행.

#### 🔑 BYOK(Bring Your Own Key) 모드 (앱스토어 배포용)

공개 배포 시 서버 호스팅·API 비용을 피하기 위해, 앱에 런타임 구성을 지원하는 **설정 UI**(상단 상태바의 톱니바퀴 아이콘)가 포함돼 있습니다.

* 상태바의 **톱니바퀴** 아이콘을 탭.
* 본인의 `LIVEKIT_URL`, 정적 `LIVEKIT_TOKEN`, 또는 동적 `TOKEN_SERVER_URL` 입력.
* **Save Settings**로 `UserDefaults`에 구성 저장.
* *참고: 구성 시 사용자 입력값이 기본 컴파일타임 키를 덮어씁니다. **Reset to Defaults**로 초기화 가능.*

#### 📱 무료 Apple Developer 계정으로 사이드로딩 (데모 영상 녹화용)

데모 영상 촬영에 유료 멤버십($99/년)은 필요 없습니다.

1. 아이폰을 USB로 Mac에 연결.
2. Xcode에서 `StarLink.xcodeproj`를 열고 **StarLink** 타겟 → **Signing & Capabilities** 선택.
3. **Team**에서 개인 Apple ID 선택(Xcode가 무료 프로비저닝 프로파일 생성).
4. 기기에서 빌드/실행.
5. 아이폰 **설정 → 일반 → VPN 및 기기 관리**에서 개발자 인증서를 **신뢰**.
   *참고: 무료 인증서로 서명한 앱은 **7일**마다 만료돼 재서명이 필요 — 테스트·데모 녹화엔 충분합니다.*

#### 백엔드 설정

1. 백엔드 디렉토리로 이동:
   ```bash
   cd backend
   ```
2. 가상환경 생성·활성화:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```
3. 의존성 설치:
   ```bash
   pip install -r requirements.txt
   ```
4. 환경변수 템플릿 복제:
   ```bash
   cp .env.example .env
   ```
5. `backend/.env`에 LiveKit 자격증명과 Gemini API Key 입력:
   ```env
   LIVEKIT_URL=wss://your-project.livekit.cloud
   LIVEKIT_API_KEY=your_livekit_api_key
   LIVEKIT_API_SECRET=your_livekit_api_secret
   GOOGLE_API_KEY=your_google_api_key
   ```

---

### 3. 시스템 실행

#### A. 통역 에이전트 실행

에이전트는 룸을 구독해 Gemini에 연결하고, 들어오는 음성을 통역해 오디오/자막을 publish합니다.
```bash
cd backend
source venv/bin/activate
python agent.py dev
```

#### B. 토큰 서버 실행 (선택)

보안 프로덕션 모드로 운영하려면, 1시간 만료 JWT를 발급하는 토큰 서버를 실행합니다.
```bash
cd backend
source venv/bin/activate
python server.py
```
기본적으로 `http://localhost:8080`에서 동작합니다.

#### C. iOS 앱 실행

에어팟 또는 블루투스 이어버드를 아이폰에 연결하고 **StarLink** 앱을 실행한 뒤, 통역 토글을 탭해 시작합니다.

---

## 🛠️ 문제 해결

### iOS 앱 문제

* **오디오가 폰 스피커/리시버로 나옴**: 이어폰이 페어링·활성 상태인지 확인. 라우팅이 실패하면 iOS 설정에서 블루투스를 토글하거나 StarLink에 블루투스 권한이 부여됐는지 확인.
* **자막이 로딩에 멈춤**: 백엔드 에이전트가 실행 중이고 LiveKit·Gemini와 안정적으로 연결됐는지 확인. Gemini API Key 쿼터가 충분한지 점검.
* **SPM 패키지 오류**: Xcode 패키지 캐시 초기화 — `File` → `Packages` → `Reset Package Caches`.

### 백엔드 에이전트 문제

* **`GOOGLE_API_KEY` not found**: `.env`에 올바른 키가 있고 로드되는지 확인.
* **에이전트는 연결되나 무음**: 지원 언어(영어·일본어·중국어)로 명확히 발화하는지 확인. 저품질 마이크 입력이나 큰 배경 소음은 에이전트의 노이즈 격리 규칙에 의해 필터링될 수 있습니다.

---

## 📄 라이선스

이 프로젝트는 [MIT License](LICENSE)를 따릅니다 — 자세한 내용은 파일을 참고하세요.

*핸즈프리 접근성과 실시간 다국어 소통을 위해 제작되었습니다.*
