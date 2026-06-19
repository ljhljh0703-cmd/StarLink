# AGENTS.md — 3.5 Live Translate 통역 앱 고도화 지시서

💡 에이전트 필독: 본 문서는 Antigravity 및 외부 코딩 에이전트가 3.5 Live Translate 기반 통역 앱을 고도화할 때 준수해야 하는 **컨텍스트 연계 및 개발 운영 지침(Operations Manual)**입니다. 새로운 세션을 시작할 때 이 문서를 최우선으로 로드하고 명시된 프로토콜을 수행하십시오.

---

## 0. 메타 가이드라인 및 서명 의무 (Acknowledge Protocol)

모든 에이전트는 본 프로젝트의 코드를 수정하거나 설계를 변경하기 전에 다음의 Acknowledge Protocol을 준수해야 합니다.

1. [AGENTS-ACK] 서명: 세션의 첫 발화 최상단에 규정된 서명 블록을 기계적으로 출력합니다.
2. Sub-brain Lookup Protocol: 로컬 또는 원격 Sub-brain의 AGENTS.md (라우팅 맵) 및 CLAUDE.md (Karpathy 4대 원칙)를 선조회합니다.
3. Pillar 정합성: 실시간성(낮은 레이턴시), 정확성(컨텍스트 보존), 오작동 방지(세션 가드레일) 3대 Pillar를 코드의 모든 라인에 강제합니다.

---

## 1. Sub-brain (LLM Wiki) 연계 아키텍처

통역 앱의 소스코드 저장소(Repo)와 Sub-brain은 아래와 같이 이원화되어 동기화됩니다.

- **Sub-brain (LLM Wiki)의 역할**
    - Decisions (wiki/projects/live-translate-decisions.md): 3.5 Live Translate API 사양, 실시간 버퍼/청크 크기, UI/UX 규칙 등 기술적 의사결정의 잠금(Lock) 출처입니다.
    - Progress (wiki/projects/live-translate-progress.md): 세션별 작업 완료 사항, Commit/Push 로그 및 다음 Task의 단일 진실 소스(SSOT)입니다.
    - Memory (wiki/projects/live-translate-memory/YYYY-WNN.md): 번역 품질 저하 이슈, 연결 끊김 및 에러 처리 패턴, 사용자 피드백 등 전술적 교훈을 주차별로 누적합니다.
    - AGENTS (wiki/projects/live-translate-AGENTS.md): 에이전트 전용 행동 및 검증 지침의 원본입니다.
- **통역 앱 Repository의 역할**
    - AGENTS.md: 본 지시서의 Repo 복제본입니다.
    - src/: 실시간 통역 엔진, WebRTC/Websocket, UI 컨트롤러가 포함된 코드 베이스입니다.
    - prompts/: 모듈화된 프롬프트 에셋 폴더입니다.
    - .codegraph/: 정적 코드 의존성 그래프를 보존하는 영역입니다.

---

## 2. 3.5 Live Translate 특화 프롬프트 체계화

3.5 Live Translate 모델(스트리밍, 양방향 오디오/텍스트)의 특성에 맞추어 프롬프트를 구조화하고 동적으로 주입할 수 있도록 고도화합니다.

### 2.1 프롬프트 모듈 구조

프롬프트는 하나의 거대한 텍스트 파일이 아닌, prompts/ 디렉토리 하위에 역할별로 모듈화하여 관리합니다.

- prompts/system_instruction.txt: 3.5 Live Translate 시스템 기본 지침 (Interpreter 페르소나 정의)
- prompts/safety_guardrail.txt: 환각 방지, 미완성 문장 처리, 민감정보 필터링 가이드라인
- prompts/contexts/: 대화 상황(Context)별 템플릿 (예: business_meeting.txt, medical_consult.txt, daily_chat.txt)
- prompts/glossaries/: 실시간 주입용 고유명사/전문용어 사전 (예: tech_industry.json, medical_terms.json)

### 2.2 실시간 컨텍스트 주입 지침

- 세션 시작(Session Initiation): system_instruction + safety_guardrail + 선택된 contexts/* 를 하나의 스트림 헤더 컨텍스트로 결합하여 Live API 세션에 주입합니다.
- 동적 용어집(Dynamic Glossary) 주입: 대화 도중 실시간 텍스트 분석(STT) 혹은 사용자 UI 조작에 의해 특정 전문 도메인이 감지되면, 관련 glossaries/*.json 내의 용어 매핑 데이터를 API의 systemInstruction 또는 cachedContent (Context Caching 활용)에 동적으로 업데이트하여 실시간 번역 품질을 보존합니다.

---

## 3. 코드 그래프 (Code Graph) 기반 아키텍처 수호

에이전트가 코드를 파악할 때 발생하는 컨텍스트 오버헤드를 줄이기 위해, .codegraph/ 및 graphify CLI를 연계하여 정적 의존성을 정의합니다.

### 3.1 통역 앱 핵심 모듈 구조

- src/core/live_session.py: 3.5 Live API 연결, WebSocket/WebRTC 세션 관리
- src/core/audio_handler.py: 마이크 입력 오디오 청크 버퍼링, 오디오 출력 제어
- src/core/text_processor.py: STT/TTS 텍스트 가공, 번역 결과 딜레이 보정
- src/prompt_engine/manager.py: prompts/ 디렉토리 에셋 로드 및 실시간 캐싱/업데이트
- src/ui/controller.py: 통역 자막 실시간 렌더링, 오디오 파형 visualizer 제어

### 3.2 Code Graph 동기화 및 검증 규칙

- 정적 의존성 수호: live_session.py 는 audio_handler.py 와 text_processor.py 에 의존하며, UI 계층은 Core 계층을 직접 제어하지 않고 이벤트/콜백을 통해서만 데이터를 수신해야 합니다.
- Graphify CLI 연동: 변경 사항이 발생할 때마다 .codegraph/ 디렉토리에 의존성 정보가 업데이트되었는지 확인하고, graphify explain 혹은 graphify query 를 활용해 코드 변경이 의존성 규칙을 위반하지 않는지 사전 검증합니다.

---

## 4. 새로운 세션의 고도화 실행 프로토콜

새로운 에이전트가 투입되어 작업을 시작할 때 다음의 5단계 파이프라인을 즉시 수행하도록 강제합니다.

### Step 1. Context Warm-up (선조회)

- wiki/hot.md 를 통해 직전 세션에서 남겨진 미결 과제를 확인합니다.
- wiki/projects/live-translate-progress.md 에서 가장 최근 of Phase 및 세션 로그를 읽고, 현재 타겟팅해야 하는 마일스톤을 식별합니다.

### Step 2. Code & Design Alignment (정합성 확인)

- 수정하려는 코드 파일의 상단에 위치한 의존성 구조를 확인합니다.
- 변경하려는 기능이 live-translate-decisions.md (SSOT)의 잠금 조항과 충돌하지 않는지 검토합니다.

### Step 3. Implementation Guardrails (개발 제약)

- 비동기 안전성: 실시간 오디오 스트리밍의 병목을 막기 위해 모든 네트워크 I/O 및 API 호출은 비동기(asyncio 등)로 구현하며, 오디오 청크 손실(Drop)을 방지하는 버퍼 가드레일을 둡니다.
- 프롬프트 분리: 하드코딩된 프롬프트 문자열은 일절 금지하며, 무조건 prompts/ 경로 내의 에셋 파일들을 참조하도록 구현합니다.

### Step 4. Verification & QA (검증)

- 작성된 코드가 3.5 Live API의 레이턴시 임계치(예: 300ms 이내 응답)를 만족하는지 검증하는 단위 테스트를 구동합니다.
- 오디오 스트리밍 연결이 예기치 않게 종료되었을 때의 재연결(Reconnection) 및 세션 복구 로직의 예외 처리(Graceful Degradation)를 검증합니다.

### Step 5. Handoff Recording (이력 관리)

- 작업 완료 후, progress.md 에 수행한 커밋 내역과 변경 지점을 기록합니다.
- 개발 중 발생한 3.5 Live API의 한계점, 프롬프트 튜닝 시 발견한 특이 사항 등은 주간 메모리(live-translate-memory/YYYY-WNN.md)에 Promote candidate: yes 마커와 함께 기록하여 Sub-brain의 지식을 지속적으로 진화시킵니다.

---

## 6. H-Core 자율 개발 규율 (Sub-brain ②Apply 검증 완료 2026-06-15)

> 본 프로젝트는 Sub-brain "모델-독립 작업 하네스(H-Core)"의 ②Apply 검증 대상이자 적용처다. backend 리팩토링 ③Gate PASS(2026-06-15, vault Claude `test_agent.py` 17 직접 재현)로 **H-Core 가 비게임 도메인에서 작동함이 실증**됐다. 앞으로 StarLink 의 *모든* 코딩 작업은 아래 H-Core 규율을 따라 자율 진행한다.

### 6.1 매 작업 H-Core 체크리스트
1. **권위·소스셋 잠금** — 작업 전 대상 파일·테스트·범위 확정.
2. **검증 계약 선행** — 동작 보존/성공 기준을 증명할 테스트를 *먼저*. 없으면 characterization test 추가 후 진행.
3. **결정 로직 ↔ 부수효과 경계** — 순수 계산/상태(`CaptionStateTracker` 류)와 I/O·오디오·네트워크·UI 분리.
4. **재현 가능성** — 동일 입력→동일 출력. 타이밍·외부상태 비결정성 격리.
5. **하위호환** — 공개 API·기존 동작 보존(additive). 깨는 변경은 명시 보고 후.
6. **과설계 기각** — 요청 범위만. 추측성 추상화·미래 대비 코드 금지.
7. **독립 단위 분할** — 마이크로 커밋, 각 단계 test green.
8. **정직한 상태 보고** — PASS/N-A/미완 구분, 실패는 출력과 함께.
9. **도구 부재 정직** — iOS XCTest 부재 시 "required/not run", 컴파일+수동으로 갈음 명시.

### 6.2 작업 종류별
- **리팩토링**: behavior-preserving 기본 — 기존 test green 유지 증명.
- **신기능**: 구현 *전* proof-family 1종 선택(unit test / 컴파일 / 수동 시뮬레이터 E2E). PR 크기로 분해.
- **버그 수정**: 재현 테스트 먼저 → 수정 → green.

### 6.3 우선 next — 자동 baseline 강화
- **iOS XCTest 타깃 추가(`project.yml`) = 최우선 인프라 투자**. 현재 iOS 는 자동 회귀 baseline 부재(컴파일+수동만)라 리팩토링/기능 회귀를 못 잡는다. XCTest 확보가 향후 *모든 iOS 작업*의 "검증 계약 선행(#2)"을 가능케 한다.
- backend 통합 동작(`process_user_transcription` 등) E2E 수동 관찰(BlackHole 가상 오디오) → 가능하면 자동화.

### 6.4 Frozen (불변 — 명시 승인 없이 변경 금지)
- 모델명 `gemini-3.5-live-translate-preview` · 시스템 인스트럭션 프롬프트 의미.
- Sub-brain vault(`~/Downloads/AI AGENT/Obsidian/Sub brain/`) 0접촉.

### 6.5 세션 종료 RETURN (Sub-brain ③Gate 대상)
- changed files · 무엇을 어떻게 · proof(test green/컴파일/수동) · behavior-preserving 증명 · 범위 밖 발견(보고만) · validation 명령+결과 · 정직 보고(N-A/미완) · risks · next.
- 자율 진행하되 **파괴적·비가역 변경(대량 삭제·구조 이전·설정 변경) 전엔 멈추고 확인**. RETURN 은 vault Claude ③Gate(4축: 동작보존·경계분리·과설계기각·정직) 대상.
