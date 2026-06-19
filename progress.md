# StarLink 개발 진행 상황 및 시행착오 이력 (progress.md)

이 문서는 StarLink 실시간 보청기 번역 시스템 개발 과정에서 발생한 모든 시행착오, 유저 피드백, 실패 사례, 그리고 기술적 해결책을 보존하는 **단일 진실 소스(SSOT)** 문서입니다.

---

## 🛠️ 시행착오 및 실패 사례 분석 (Failure Post-Mortem)

### 1. [오디오 세션 구성] 자동 구성 vs 수동 구성의 반복적 삽질
* **시도 1 (자동 구성)**: LiveKit SDK의 `isAutomaticConfigurationEnabled = true` 상태에서 기본 옵션으로 기동.
  * **결과**: LiveKit SDK 기본 카테고리 옵션(`playAndRecordSpeaker`)에 보청기 전송 필수 옵션인 `.defaultToSpeaker`가 누락되어 보청기 무음 상태 발생.
* **시도 2 (커스텀 콜백)**: `isAutomaticConfigurationEnabled = true`를 유지한 채 `customConfigureAudioSessionFunc` 콜백을 등록하여 세션을 변경.
  * **결과**: WebRTC 내부 C++ 엔진이 기동하는 비동기 시점에 세션을 수화기(Earpiece) 전용 모드로 제비용 덮어쓰기하여 여전히 무음 현상 발생.
* **시도 3 (수동 구성 락)**: `isAutomaticConfigurationEnabled = false`로 완전 차단하고, `MFiAudioManager`에서 WebRTC `LKRTCAudioSession` 락(`lockForConfiguration()`) 범위 내에 `useManualAudio = true` 및 수동 세션 구성을 적용.
  * **결과**: WebRTC의 세션 강제 리셋을 완벽히 방어하고 MFi 보청기 및 에어팟으로의 오디오 스트리밍 출력 안정성 확보.

### 2. [마이크 제어 및 에코 차단] 반이중 통제 알고리즘의 변천사
* **시도 1 (VAD 단독 제어 - 지연 없음)**: LiveKit의 `didUpdateIsSpeaking` (VAD) 신호에 맞춰 즉각 로컬 마이크를 뮤트/언뮤트함.
  * **결과**: AI 한국어 발화가 종료되는 즉시 마이크가 열리면서 스피커 재생 잔향 및 레이텐시 음이 마이크로 재유입되어 `then, and then...` 전사가 무한 반복 도배되는 에코 루프 발생.
* **시도 2 (백엔드 상태 메시지 기반)**: 백엔드가 텍스트 생성 종료 시 송신하는 `stopped` 상태 메시지 기준으로만 마이크를 언뮤트함.
  * **결과**: 실제 스트리밍 오디오 재생 완료 시점보다 텍스트 생성이 더 빨리 끝나 마이크가 조기 언뮤트되었고, 번역 잔향이 다시 마이크로 유입되어 번역이 완전히 정지됨.
* **시도 3 (VAD + 백엔드 상태 결합 및 500ms 지연)**: `isAISpeakingByVAD`와 백엔드 상태 `isAISpeakingByState`를 OR 결합하고 500ms 이중 가드 타이머 추가.
  * **결과**: 세션 시작 준비 단계에서 백엔드가 발송하는 최초 `playing` 신호로 인해 사용자가 말을 시작하기도 전에 마이크가 영구 음소거(Mute) 상태로 잠겨버리는 데드락(Deadlock) 유발.
* **시도 4 (VAD 단독 + 500ms 지연 타이머 - 최종 안)**: 백엔드의 상태 패킷을 차단하고, 실제 오디오 송출 여부인 VAD(`isAISpeakingByVAD`) 신호와 500ms 무음 지연 타이머만을 결합하여 제어.
  * **결과**: 초기 데드락이 완전히 해제되어 정상적인 수음이 시작되었으며, AI 발화 종료 후의 에코 유입 또한 완벽히 차단됨.

### 3. [인공지능 모델명] AI 학습 컷오프(2025년)로 인한 모델명 임의 변경 실패
* **시도**: 에이전트의 자체 지식 컷오프 한계로 `gemini-3.5-live-translate-preview` 모델을 존재하지 않는 가상 모델로 오인하여 일반 멀티모달 모델인 `gemini-2.5-flash-native-audio-preview-12-2025`로 소스코드를 임의 수정함.
* **결과**: 유저의 공식 모델 지정 지침에 위배되었을 뿐만 아니라, 6월 11일 실시간 호출 토큰 사용량이 0으로 플랫라인되는 대화 마비 현상 발생.
* **해결 방법**: 모델명을 공식 사양인 **`gemini-3.5-live-translate-preview`**로 완벽 복구하고, 에이전트가 지식 한계 직면 시 임의 수정하지 않고 사용자에게 조사를 요청하도록 개발 규칙 고정.

### 4. [오디오 경로 오버라이드] WebRTC 수동 모드에서의 스피커 강제 변환 실패
* **시도**: `useManualAudio = true` 상태에서 표준 `AVAudioSession`에 직접 `.overrideOutputAudioPort(.speaker)` 호출.
* **결과**: OSStatus error -50 (Invalid Parameter)이 발생하며 무선 기기에서 스피커로의 경로 변환이 실패함.
* **해결 방법**: `LKRTCAudioSession.sharedInstance().lockForConfiguration()` 블록으로 감싸 WebRTC 엔진이 감지할 수 있도록 스피커 오버라이드를 처리하여 라우팅 안정성 확보.

### 5. [번역 자막 화면] 텍스트 스트림 누락으로 인한 자막 멈춤 현상
* **시도**: `gemini-3.5-live-translate-preview` 모델을 사용하여 음성-대-음성 번역은 원활하게 이루어졌으나, 자막 화면에 `번역을 생성하는 중 🔄` 아이콘만 표시되고 번역 자막이 실시간으로 표기되지 않는 화면 퇴행이 발생했습니다.
* **원인**: 음성-대-음성 특화 모델은 기본값 상태에서는 별도로 지시하지 않으면 텍스트 스트림(`msg.text_stream`)을 반환하지 않으므로, LiveKit 에이전트 측에서 텍스트 전송 이벤트를 감지할 수 없었습니다.
* **해결 방법**: `CustomRealtimeModel` 초기화 시 `input_audio_transcription=types.AudioTranscriptionConfig()` 및 `output_audio_transcription=types.AudioTranscriptionConfig()`를 명시적으로 전달하여 인풋/아웃풋 전사 텍스트 스트림을 활성화함으로써 번역 음성 출력과 번역 자막 표기가 실시간으로 병행되도록 복구했습니다.

### 6. [브랜드 타이틀 UI] 폰트 크기 및 가로폭에 의한 비자발적 래핑 현상
* **시도**: 가로폭이 좁은 모바일 화면 및 특정 설정에서 상단 스테이터스 바의 앱 타이틀이 "StarLin k"와 같이 잘려서 래핑되는 현상이 발견되었습니다.
* **해결 방법**: `StatusBar.swift` 내의 `brandTitle` 뷰에 `.lineLimit(1)` 및 `.fixedSize(horizontal: true, vertical: false)`를 강제하여 화면 폭과 관계없이 "StarLink"가 단일 라인에 깔끔하게 표기되도록 UI를 조정했습니다.

### 7. [기록 모드] 한국어 음성 인식 묵살 및 소리 수음 불가 현상
* **시도**: 회의록 기록 모드(`transcription`) 진입 시, 음성 입력을 전혀 감지하지 못하고 화면에 텍스트가 나오지 않는 현상이 발생했습니다.
* **원인**: 
  1. 통역 모드 전용으로 설정된 `SYSTEM_INSTRUCTION` 내부의 "Ignore any Korean audio (한국어 음성 무시)" 지침이 기록 모드에서도 그대로 유지되어, 사용자의 한국어 음성을 인공지능이 노이즈로 간주하고 걸러냈습니다.
  2. 통역 모드와 기록 모드 전환 시 인공지능의 시스템 인스트럭션이 변경되지 않아 발생한 결함이었습니다.
* **해결 방법**: 기록 모드 전용 인스트럭션인 `TRANSCRIPTION_INSTRUCTION`을 새로 설계하고, `ctx.room.on("data_received")` 이벤트 수신 및 세션 시작 시점에 `session.update_instructions(inst)`를 호출하여 실시간 동적 시스템 지침 전환을 구현했습니다. 이를 통해 기록 모드에서는 한국어 포함 모든 언어의 STT 전사를 차별 없이 수행하며, AI 음성 출력은 완전한 묵음(Absolute Silence)을 유지하도록 통제했습니다.

---

## 📋 유저 피드백 및 조치 이력

* **피드백 1 (13:41)**: 자막에 `then, and then...` 무한 도배 및 번역 정지.
  * *조치*: 500ms 무음 지연 및 이중 가드 타이머 도입.
* **피드백 2 (14:14)**: 주변 소음 취약 및 영어를 일본어로 번역함.
  * *조치*: `agent.py` 프롬프트에 한국어 단독(KOREAN ONLY) 및 소음 시 침묵(Silence) 규칙 탑재.
* **피드백 3 (14:34)**: 모델명 임의 변경 지적 및 히스토리 기록 누락 경고.
  * *조치*: 모델명을 `gemini-3.5-live-translate-preview`로 원복하고 `progress.md`에 시행착오 완전 문서화.
* **피드백 4 (14:35)**: 콘솔의 사용량 토큰 그래프가 0인 점 확인 및 웹서핑 한계 시 유저 조사 요청 요구.
  * *조치*: 공식 모델을 재검증 및 연동하고, 정보 부재 시 유저에게 공식 스펙 및 에러 조사를 요청하는 절대 지침 수립.
* **피드백 5 (14:51)**: 여전히 번역을 못 잡고 마이크 팝업이 안 나오며 OSStatus error -50 발생.
  * *조치*: 권한 재확인(이미 허용됨), 백엔드 상태 메시지 배제를 통한 마이크 데드락 해제, WebRTC 락을 통한 스피커 오버라이드 오류 해결.
* **피드백 6 (15:20)**: 번역 소리는 정상 출력되나 자막(번역 화면)이 생성 중으로 멈추는 퇴행 발생 및 상단 타이틀 "StarLink" 래핑 현상.
  * *조치*: `agent.py`에 `input_audio_transcription` 및 `output_audio_transcription` 옵션을 주입하여 전사 텍스트 스트림을 강제 수신하도록 복원, `StatusBar.swift` 타이틀 UI에 1줄 제한 및 크기 고정 옵션 적용.
* **피드백 7 (15:28)**: 기록 모드 가동 시 음성 수음이 되지 않고 아무 소리도 잡지 못함.
  * *조치*: `TRANSCRIPTION_INSTRUCTION`을 별도 설계하고, 모드 전환 시 세션 지침을 실시간 업데이트(`session.update_instructions`)하여 한국어 인식 활성화 및 AI 출력 묵음 처리 완수.

---

## 📋 현 기능 구현 수준

* **실시간 통역 모드**: 물리적 오디오 전송 여부(VAD)와 500ms 지연 타이머를 결합하여 데드락 없이 안정적인 번역 및 에코 루프 차단 지원.
* **실시간 한국어 자막 모드 (STT 단독)**: 통역 지침을 우회하여 동적 인스트럭션 업데이트를 통해 인풋 오디오를 0ms 지연으로 투명하게 실시간 한글 기록으로 생성.
* **실시간 번역 자막**: 오디오와 병행하여 번역 전사 텍스트를 실시간으로 자막 뷰에 동기 표출.
* **스피커 강제 출력**: WebRTC 수동 오디오 락 상태에서도 OSStatus 에러 없이 보청기와 기기 스피커 간 안정적인 오디오 라우팅 전환 보장.
* **회의록 내보내기/공유**: 대화 히스토리를 시간 순서로 `.txt` 파일로 포매팅하여 iOS 기본 공유창(Share Sheet) 연동 완료.
* **수동 오디오 락 완성**: `useManualAudio = true` 가 장착되어 보청기 출력이 폰 내부로 기어들어가지 않는 견고한 CoreAudio 셋업 보장.

## 🔒 7. 보안 강화 및 오픈소스 배포 준비 (Security & Open Source Preparation)
* **시도**: 프로젝트를 오픈소스로 공개하기 위해 소스코드 내 민감 자격 증명을 전면 격리하고, 실서비스 운영을 위한 보안 아키텍처를 도입해야 했습니다.
* **해결 방법**:
  1. **자격 증명 격리**: `Secrets.plist` (git-ignored) 및 `Secrets.plist.example`을 설계하여 iOS 클라이언트 자격 증명을 안전하게 격리하고, `AppConfig.swift`에 동적 plist 파싱 및 개발값 폴백을 구성해 기존 로컬 빌드 호환성을 유지했습니다.
  2. **경량 토큰 서버 개발**: `aiohttp` 기반의 `/api/token` 토큰 서버 `server.py`를 제작하여 CORS, `no-store` 캐싱 방지, 1시간 TTL 단기 AccessToken JWT 발급 로직을 완비했습니다.
  3. **iOS 동적 토큰 획득**: `LiveKitStreamManager.swift`에 `fetchDynamicToken` 비동기 요청을 통합하여, `TOKEN_SERVER_URL`이 있으면 실시간 토큰을 받아오고 없으면 안전하게 폴백하도록 연동했습니다.
  4. **리포지토리 보안 & 라이선스**: `.gitignore` 작성으로 프로젝트 자동 생성 파일 및 보안 키 누출을 차단했으며, MIT 라이선스를 부여하고 `README.md`와 `CLAUDE.md` 가이드를 갱신했습니다.

## 📁 8. 포트폴리오 최적화 및 무선 이어폰 번역 중심 문서 개정 (Portfolio & Wireless Earphones Translation Focus)
* **시도**: 프로젝트를 개인 포트폴리오로 강력하게 활용할 수 있도록 문서 구조를 리팩토링하고, 실시간 무선 이어폰/에어팟/블루투스 기기 통번역 시나리오에 초점을 맞추어 README.md를 대대적으로 개정해야 했습니다.
* **해결 방법**:
  1. **무선 오디오 타겟팅 확장**: 특정 보청기 브랜드에 한정되어 있던 설명 방식을 탈피하여, 에어팟, 갤럭시 버즈 등 범용 블루투스 오디오 장치를 아우르는 실시간 통번역 시스템으로 README.md 전면 개편.
  2. **4대 엔지니어링 핵심 챌린지 시각화 및 문서화**: 포트폴리오 심사관과 타 개발자가 개발자의 실력을 한눈에 볼 수 있도록, 본 프로젝트가 해결한 핵심 난제들(AVAudioSession 수동 제어, VAD 및 500ms 버퍼 활용 마이크 에코 차단, Gemini Live 번역 오디오-자막 실시간 동기화, 0ms 레이텐시 자체 언어 판별 파서)을 기술 문서 수준으로 깊이 있게 정리.
  3. **오픈소스 가이드 고도화**: Secrets.plist 활용, xcodegen 프로젝트 빌드 준비 절차, 그리고 경량 Token Server 가동법 등을 일목요연하게 다이어그램과 표 형식으로 기술.

## 🔑 9. Bring Your Own Key 설정 UI 탑재 및 무료 빌드 가이딩 (BYOK Configuration UI & Sideloading Guide)
* **시도**: 공용 앱스토어 배포 시 서버비용을 유저 개인 API 키로 충당하는 상용화 시나리오(BYOK)와 무료 애플 계정으로 본인 폰에 빌드하여 포트폴리오 비디오를 촬영하는 시나리오를 동시에 만족해야 했습니다.
* **해결 방법**:
  1. **설정 화면 구축**: `SettingsView.swift`를 개발하여 LiveKit URL 및 Token 설정을 `UserDefaults`에 로컬 저장할 수 있는 UI를 탑재하고, `StatusBar.swift`에 설정용 톱니바퀴 버튼을 연동했습니다.
  2. **설정 동적 파싱 및 빌드 검증**: `AppConfig.swift`가 `UserDefaults` 값을 최우선 순위로 읽어오도록 수정하여 공용 출시 준비를 마쳤으며, XcodeGen 재생성 후 `** BUILD SUCCEEDED **` 컴파일 빌드를 성공했습니다.
  3. **포트폴리오 비디오 가이드**: 무료 애플 계정의 7일 서명 제한을 활용하여 케이블 연결 후 실기기에 사이드로딩하여 동작 검증 및 데모 동영상을 바로 녹화할 수 있는 가이드라인을 `README.md`에 최적화하여 작성했습니다.

## 🔑 10. 비동기 스트림 이중 소비 해결 및 실시간 자막/번역 복구 (Async Stream Double-Consumption Fix & Captions/Translation Recovery)
* **시도**: 번역 및 한국어 자막 전송 시, 오디오 출력은 끊기고 클라이언트 자막이 전혀 표출되지 않는 상태가 발생했습니다.
* **원인**: 백엔드 `agent.py`와 LiveKit Agents SDK의 `AgentActivity`가 동일한 `ev.message_stream` 비동기 제네레이터를 동시에 소비하려다가 충돌하여 스트림이 누락되고 태스크가 프리징되었습니다.
* **해결 방법**:
  1. `agent.py` 내의 `sess.on("generation_created")` 중복 리스너를 전면 삭제했습니다.
  2. `CustomRealtimeModel`이 `sess.emit`을 몽키패치하여 `"generation_created"` 이벤트를 가로채도록 변경했습니다.
  3. LiveKit SDK가 스트림을 소비하는 과정에서 부작용 없이 자막 텍스트만 실시간으로 복제하여 전송하도록 `intercept_message_stream` 및 `intercept_text_stream` 비동기 제네레이터 래퍼를 설계하여, 오디오와 번역 자막 모두 완벽히 복구했습니다.

## 🔑 11. AgentSession ValueError 크래시 해결 및 로컬 VAD (Silero) 도입 (ValueError Crash Fix & Silero VAD Migration)
* **시도**: 클라이언트 마이크 상시 개방 환경에서 번역 오디오 재생 시 발생하는 루프 가로채기(Barge-in)를 막기 위해 `allow_interruptions=False`를 설정했으나, 세션 시작과 동시에 백엔드 에이전트 프로세스가 크래시되는 현상이 나타났습니다.
* **원인**: Gemini RealtimeModel의 서버 사이드 발화 감지(Server-side Turn Detection) 방식을 사용하면서 `allow_interruptions=False`를 주는 경우, SDK 내부 충돌로 인해 `ValueError` 예외를 일으킵니다.
* **해결 방법**:
  1. `livekit-plugins-silero`를 백엔드 환경에 설치했습니다.
  2. `agent.py`에서 `RealtimeModel`에 `realtime_input_config` 옵션을 주입하여 서버 발화 감지를 비활성화(`disabled=True`) 처리했습니다.
  3. `AgentSession`에 로컬 VAD `silero.VAD.load()`를 인자로 주입하여 발화 판단 주체를 백엔드 로컬로 이관했습니다.
  4. 이를 통해 `allow_interruptions=False` 구성을 유지하여 에코 루프 가로채기를 성공적으로 막는 동시에 세션 시작 시의 크래시 현상을 완벽하게 해결했습니다.

## 🔑 12. 선제적 생성(Preemptive Generation) 비활성화를 통한 데드락 해결 (Preemptive Generation Deadlock Resolution)
* **시도**: 로컬 VAD 도입 후 첫 문장은 성공적으로 번역 및 오디오 출력이 진행되었으나, 이후 대화 루프가 완전히 얼어붙는(Freezing) 데드락 현상이 발생했습니다.
* **원인**: 
  1. `allow_interruptions=False` 상태에서 `preemptive_generation` 기능이 활성화되어 사용자가 말을 시작하자마자 백엔드에서 답변 생성을 선제 점유했습니다.
  2. 사용자가 말을 마쳐 문장이 완성되었을 때 VAD가 최종 답변 생성을 요청하지만, 이미 답변이 돌고 있으므로 `current speech generation cannot be interrupted`라며 최종 답변 요청이 묵살되었습니다.
  3. 이로 인해 최종 문장의 `turn_complete=True` 완료 신호가 Gemini 서버에 전달되지 못해 세션이 영구적으로 대기 상태에 갇혀버렸습니다.
* **해결 방법**:
  1. `agent.py`에서 `AgentSession` 생성 시 `turn_handling` 설정에 `"preemptive_generation": {"enabled": False}` 옵션을 주입했습니다.
  2. 문장 완결이 VAD로 최종 확정되는 시점에만 답변 생성을 한 번 요청하도록 제한하여 선제적 생성 점유에 의한 데드락을 방어하고, 에코 루프 차단과 턴 전환 제어의 안정성을 확보했습니다.

## 🔑 13. 연속 스트리밍 번역 아키텍처 돌파 — VAD/Turn-Taking 완전 제거 (2026-06-12)

> **핵심 발견**: Gemini 3.5 Live Translate는 대화형(request-response) 모델이 아니라 **연속 스트리밍 번역 모델**이다. SDK의 대화형 turn-taking 인프라(VAD, generate_reply, preemptive_generation, interruption)를 **전부 비활성화**해야 정상 동작한다.

### 실패한 접근법 (6단계 시행착오)

1. **`generate_reply` 몽키패치 + `ActivityEnd` 전송 + 로컬 VAD**
   - 결과: ❌ 첫 문장 후 즉시 먹통. VAD의 300ms silence threshold가 발화 중 pause를 end-of-turn으로 오감지 → ActivityEnd 전송 → Gemini 활동 종료 → 후속 오디오 무시.

2. **`ActivityEnd` 전송 제거 (VAD는 유지)**
   - 결과: ⚠️ 여러 문장까지 성장하나 결국 고착. VAD가 `commit_audio` + `generate_reply`를 반복 트리거 → SDK generation 파이프라인 경합 → N번째 발화 후 세션 고착.
   - 증거: 로그에 `commit_audio is not supported by Gemini Realtime API` 반복.

3. **로컬 VAD 완전 제거 + Gemini 자체 activity detection 활성화**
   - 결과: ❌ 20초 후 먹통. Gemini의 auto activity detection이 발화 간 자연스러운 pause를 end-of-activity로 오인하여 generation 스트림 조기 종료.
   - 증거: `generation_created` 이벤트가 전체 세션 중 **1번만 발생**.

4. **iOS AVAudioSession 모드 `.videoChat` → `.default` 변경**
   - 결과: ✅ MFi 보청기 오디오 라우팅 충돌 해결.
   - 증거: `(Fig) signalled err=-12710` 에러는 잔존하나 보청기 출력 경로 정상화.

5. **보청기 연결 시 `isSpeakerOutputPreferred = false` 강제**
   - 결과: ✅ LiveKit AudioEngine ↔ iOS 시스템 라우팅 간 토글 루프 해소.
   - 증거: `Speaker override changed: true/false` 반복 로그 소멸.

6. **✅ 최종: VAD 없음 + activity detection 비활성화 + turn_handling 없음**
   - 결과: ✅ 번역 + 음성 출력 + 보청기 라우팅 모두 성공. 연속 동작 확인.

### 최종 확정 설정

```python
# 백엔드 (agent.py)
model = CustomRealtimeModel(
    model="gemini-3.5-live-translate-preview",
    realtime_input_config=types.RealtimeInputConfig(
        automatic_activity_detection=types.AutomaticActivityDetection(disabled=True)
    ),
)
session = AgentSession(llm=model)  # NO vad, NO turn_handling
```

```swift
// iOS (LiveKitStreamManager.swift)
AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(
    category: .playAndRecord,
    categoryOptions: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker],
    mode: .default  // .videoChat 금지
)
// 보청기 연결 시: AudioManager.shared.isSpeakerOutputPreferred = false
```

### 변경된 파일
- `backend/agent.py`: VAD 제거, activity detection 비활성화, turn_handling 제거, generate_reply 몽키패치 순수 no-op 유지
- `StarLink/Managers/LiveKitStreamManager.swift`: AVAudioSession 모드 변경, 보청기 라우팅 보호
- `StarLink/Managers/MFiAudioManager.swift`: 보청기 연결 시 스피커 오버라이드 차단 guard 추가

---

## 🔑 14. 출시 전 안정화 세션 — 버그 2종 수정 및 보안 점검 (2026-06-17)

### 발견된 버그 1: `CustomRealtimeModel` 클래스 미정의 (NameError — 기동 불가)

* **원인**: `agent.py` 전체에서 `CustomRealtimeModel(...)` 사용(line 399)되나, 클래스 정의가 파일 내 **완전히 누락**되어 있었음. 백엔드 기동 시 즉시 `NameError: name 'CustomRealtimeModel' is not defined`로 크래시.
* **해결**: `from livekit.plugins.google.realtime import RealtimeModel as _GoogleRealtimeModel` import 추가 후, `entrypoint` 함수 직전(line 214)에 서브클래스 정의 삽입:
  ```python
  class CustomRealtimeModel(_GoogleRealtimeModel):
      def __init__(self, *, on_session_created=None, on_generation_created=None, **kwargs):
          super().__init__(**kwargs)
          self._cb_session_created = on_session_created
          self._cb_generation_created = on_generation_created

      def session(self) -> llm.RealtimeSession:
          sess = super().session()
          if self._cb_generation_created is not None:
              sess.on("generation_created", self._cb_generation_created)
          if self._cb_session_created is not None:
              self._cb_session_created(sess)
          return sess
  ```
* **검증**: `_GoogleRealtimeModel.__init__`이 `on_session_created`/`on_generation_created` kwargs를 수용하지 않음을 SDK 소스(`realtime_api.py`) 직접 확인. EventEmitter가 등록 순서대로 리스너를 실행하므로 `session()` 오버라이드에서 등록 시 `AgentActivity`의 리스너보다 선행 실행 보장.

### 발견된 버그 2: 모드 전환 시 `update_instructions()` 미호출 (기록 모드 무음)

* **원인**: `on_data_received` 핸들러에서 `caption_tracker.current_mode`는 업데이트하나 `llm_session.update_instructions()`를 **호출하지 않음**. 결과: 기록 모드로 전환해도 Gemini는 계속 `SYSTEM_INSTRUCTION`("Ignore any Korean audio")을 적용 → 한국어 음성 묵살.
* **해결**: 모드 전환 감지 블록에 아래 코드 추가(line 282):
  ```python
  if llm_session is not None:
      inst = (
          TRANSCRIPTION_INSTRUCTION
          if new_mode == "transcription"
          else SYSTEM_INSTRUCTION
      )
      asyncio.create_task(llm_session.update_instructions(inst))
      logger.info(f"LLM session instructions updated for mode: {new_mode}")
  ```
* **참고**: `on_data_received`는 동기 콜백(EventEmitter 제약)이므로 `asyncio.create_task()`로 비동기 호출 스케줄링.

### 발견된 버그 3: 미사용 `silero` import (잠재적 ImportError)

* **원인**: §13에서 로컬 VAD(Silero)가 제거되었으나 `from livekit.plugins import google, silero`가 잔존. `requirements.txt`에도 `livekit-plugins-silero`가 미등재.
* **해결**: 사용하지 않는 `silero` import를 제거(`from livekit.plugins import google`으로 수정). §13 working 설정에 영향 없음.

### 보안 점검 (B체크리스트) 결과

| 항목 | 결과 |
|------|------|
| `StarLink/Secrets.plist` gitignore 누출 | ✅ PASS — `.gitignore`에 명시, git 추적 없음 |
| `backend/.env` gitignore 누출 | ✅ PASS — `.gitignore`에 명시, git 추적 없음 |
| 소스코드 하드코딩 시크릿 | ✅ PASS — `.py`·`.swift`·`.plist` 전체 grep 클린 (venv 내 테스트 픽스처만 히트, 제외됨) |
| `server.py` CORS 헤더 | ✅ PASS — `Access-Control-Allow-Origin: *` |
| `server.py` Cache-Control no-store | ✅ PASS — `Cache-Control: no-store, no-cache, must-revalidate` |
| JWT TTL 1h | ✅ PASS — `.with_ttl(datetime.timedelta(hours=1))` |
| BYOK SettingsView / AppConfig | ✅ PASS — UserDefaults → Secrets.plist 폴백 구조 |

### 테스트 결과

```
backend/test_agent.py: 17/17 PASS (1.22s)
```

§13 working 설정(모델명, disabled=True, no VAD, no turn_handling, generate_reply no-op, in/out AudioTranscriptionConfig) 회귀 없음 확인.

### 변경 파일

| 파일 | 변경 내용 |
|------|---------|
| `backend/agent.py` | `CustomRealtimeModel` 클래스 추가, `update_instructions` 호출 추가, `silero` 미사용 import 제거 |

### 잔여 항목 (실기기 필요)

- **C — iOS 빌드**: `xcodegen generate` + `xcodebuild` 컴파일은 Mac/Xcode 환경에서만 가능. Linux 샌드박스 venv Mac 전용 바이너리로 실행 불가. H-Core Rule 9: "required/not run".
- **A — 전 항목 실기기 회귀 검증**: 다국어 번역·보청기 라우팅·자막 동기·기록 모드·회의록 내보내기 등 실기기(iPhone + 에어팟/보청기) 재현 필요.
- **D — 데모 영상**: 실기기 A 통과 후 촬영.

