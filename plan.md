# StarLink 개선 계획 (plan.md)

이 문서는 실시간 보청기 번역 스트리밍 오류(출력 무음, 번역 멈춤)를 해결하기 위한 구체적인 기술 설계 및 조치 계획을 기술합니다.

## 1. 당면 문제 진단 및 원인 분석

### A. 출력 무음 문제
* **원인**: `LiveKit`이 연결될 때 WebRTC 엔진이 내부적으로 `AVAudioSession` 카테고리와 모드를 자체 규칙에 따라 재구성합니다.
* **현상**: `isAutomaticConfigurationEnabled = false`로 설정했더라도 WebRTC의 `RTCAudioSession`에 `useManualAudio = true`를 세팅하지 않으면, WebRTC는 특정 시점에 세션을 수화기(earpiece) 전용 모드로 덮어써서 에어팟이나 보청기로 소리가 가지 않고 무음이 됩니다.
* **해결책**: `MFiAudioManager.swift`에서 `rtcAudioSession.useManualAudio = true`를 확실히 선언하고, 모든 오디오 구성을 개발자가 통제하도록 보장합니다.

### B. 번역이 하다가 멈추는 문제
* **원인**: 백엔드 에이전트(`agent.py`)는 **텍스트 생성 종료 시점**에 마이크 언뮤트 신호(`stopped`)를 보냅니다. 하지만 실제 **음성 스트리밍 재생**은 텍스트 생성보다 느리게 종료됩니다.
* **현상**: AI가 아직 보청기나 스피커로 한국어 번역을 재생하고 있는 도중에 마이크가 언뮤트되어, 번역 음성이 그대로 마이크로 재유입(에코 루프)됩니다. `agent.py`는 자신의 번역 음성이 유입되면 시스템 지침(한국어 무시 가드레일)에 의해 침묵 상태로 전환되어 번역이 완전히 멈춘 것처럼 보이게 됩니다.
* **해결책**:
  1. 백엔드 전송 신호에 의존하지 않고, iOS 클라이언트 단에서 **실제 Agent의 음성 송출 상태(`isSpeaking`)**를 감지하여 마이크를 뮤트/언뮤트합니다.
  2. LiveKit `RoomDelegate`의 `room(_:participant:didUpdateIsSpeaking:)` 이벤트를 구독하여, 번역 에이전트가 말을 하고 있을 때만 로컬 마이크를 뮤트하고, 말하기를 멈추면 즉시 언뮤트합니다.

---

## 2. 세부 변경 계획

### [Component 1] iOS 클라이언트 (`LiveKitStreamManager.swift`)
* `handleAudioStateChange`에 의존하던 반이중 로직을 제거 또는 백업화하고, `RoomDelegate`의 `didUpdateIsSpeaking` 메서드 구현.
* RemoteParticipant(번역 에이전트)의 `didUpdateIsSpeaking` 값이 변경될 때마다 로컬 마이크 트랙의 `mute()` / `unmute()`를 실시간 호출하도록 설계.

### [Component 2] iOS 클라이언트 (`MFiAudioManager.swift`)
* `configureAndActivate()` 시점에 `rtcAudioSession.useManualAudio = true` 적용.
* `AVAudioSession` 대신 `rtcAudioSession`을 통해 오디오 구성을 수행하여 WebRTC 내부 오디오 파이프라인과의 정렬 유지.

---

## 3. 핵심 규칙 및 개발 가이드라인
* **공식 번역 특화 모델 고정**: `gemini-3.5-live-translate-preview` 모델명을 소스코드 및 설정에서 절대로 다른 모델(예: `gemini-2.5-flash-...`)로 변경하지 마십시오.
* **지식/웹서핑 제약 시 유저 요청**: 새로운 모델의 상세 파라미터나 API 스펙을 탐색하는 데 있어 웹서핑 혹은 모델 지식 컷오프(2025년)의 제약이 느껴진다면, 추측하여 코드를 훼손하지 말고 **사용자에게 공식 문서, API 가이드 또는 에러 콘솔 로그의 조사를 요청**하십시오.

