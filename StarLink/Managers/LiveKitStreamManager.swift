// MARK: - LiveKitStreamManager.swift
// StarLink — Gemini Live Hearing Aid Translation
//
// Manages the full LiveKit room lifecycle: connection, mic
// publishing, remote-track subscription, data-channel caption
// parsing, and graceful teardown.
//
// Architecture
// ────────────
// • The Python agent joins the same LiveKit room, bridges mic
//   audio to Gemini 3.5 Live Translate, and publishes the
//   translated Korean audio back as a remote track.
// • Text captions arrive over the LiveKit data channel as UTF-8.
// • LiveKit SDK auto-plays subscribed remote audio tracks, so
//   this manager only needs to log subscription events.
// • `MFiAudioManager` is injected to coordinate AVAudioSession
//   activation/deactivation around the connection lifecycle.
// ──────────────────────────────────────────────────────────────────

import AVFoundation
import Combine
import LiveKit
import LiveKitWebRTC
import os
import UIKit

/// The operational mode of the StarLink application.
enum AppMode: String, Codable {
    case translation = "translation"
    case transcription = "transcription"
}

/// Observable manager that owns the LiveKit ``Room`` and exposes
/// connection / translation state to SwiftUI.
@MainActor
final class LiveKitStreamManager: ObservableObject {

    // MARK: – Published State

    /// `true` while the room is in the `.connected` state.
    @Published private(set) var isConnected: Bool = false

    /// `true` after ``startTranslation()`` succeeds and until
    /// ``stopTranslation()`` completes.
    @Published private(set) var isTranslating: Bool = false

    /// The most recent caption text (partial or final).
    @Published private(set) var currentCaption: String = ""

    /// Rolling history of caption entries, capped at
    /// ``AppConfig/maxCaptionHistory``.
    @Published private(set) var captionHistory: [CaptionEntry] = []

    /// Non-nil when the last connection attempt or an in-flight
    /// session encountered an error.
    @Published private(set) var connectionError: String? = nil

    /// Real-time connection quality reported by the LiveKit SFU.
    @Published private(set) var connectionQuality: ConnectionQuality = .unknown

    /// The current operational mode (translation or transcription).
    @Published var appMode: AppMode = .translation

    // MARK: – Dependencies

    /// Injected audio-session manager used to activate / deactivate
    /// the session around the LiveKit connection lifecycle.
    private let audioManager: MFiAudioManager

    private var cancellables = Set<AnyCancellable>()

    // MARK: – Private

    /// The LiveKit room instance.  `nil` when disconnected.
    private var room: Room?

    private let logger = Logger(
        subsystem: "com.starlink.stream",
        category: "LiveKitStreamManager"
    )

    private var isAISpeakingByVAD: Bool = false
    private var isAISpeakingByState: Bool = false
    private var unmuteDebounceTimer: Timer?

    // MARK: – Lifecycle

    /// - Parameter audioManager: The shared ``MFiAudioManager``
    ///   instance that configures AVAudioSession for hearing-aid
    ///   routing.
    init(audioManager: MFiAudioManager) {
        self.audioManager = audioManager

        // Listen to appMode changes and propagate to backend if connected
        $appMode
            .dropFirst()
            .sink { [weak self] newMode in
                Task { [weak self] in
                    await self?.sendModeChange(mode: newMode)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: – Public API

    /// Connects to the LiveKit room and begins streaming the
    /// microphone to the translation agent.
    ///
    /// If a session is already active this method is a safe no-op
    /// that logs a warning rather than double-connecting.
    func startTranslation() async {
        guard !isTranslating else {
            logger.warning("startTranslation called while already translating — ignoring")
            return
        }

        // 1. Reset error state from any previous failure.
        connectionError = nil

        // 1.5. Clean up any stale room from a previous session.
        // On app restart or rapid stop→start, the old Room object may
        // still exist. Disconnect it before creating a new one.
        if room != nil {
            logger.info("Cleaning up stale room before reconnection…")
            await cleanupRoom()
        }

        // 1.6. Clear caption state for a fresh session.
        // The backend generates segment IDs starting from turn-1 for each session.
        // Without clearing, old entries collide with new ones.
        captionHistory.removeAll()
        currentCaption = ""

        // 2. Request microphone permission using iOS 17+ AVAudioApplication API.
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied {
            logger.error("❌ Microphone permission previously denied")
            connectionError = "마이크 권한이 비활성화되어 있습니다. 설정 앱에서 허용해주세요."
            
            // Redirect to settings automatically
            await MainActor.run {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            return
        }
        
        let hasPermission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        guard hasPermission else {
            logger.error("❌ Microphone permission denied by user prompt")
            connectionError = "마이크 권한이 비활성화되어 있습니다. 설정 앱에서 허용해주세요."
            return
        }

        // 3. Configure LiveKit's shared AudioManager with our custom hearing-aid optimized configurations.
        // Enable automatic configuration to let LiveKit handle activation/deactivation smoothly without deadlocks.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(
            category: .playAndRecord,
            categoryOptions: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker],
            mode: .default  // ⚠️ MFi 보청기 호환: .videoChat은 VoIP 최적화 모드로 보청기 스트리밍 프로토콜과 충돌 (err=-12710 유발)
        )
        // ⚠️ [보청기 라우팅 보호] 보청기 연결 시 isSpeakerOutputPreferred를 반드시 false로 유지.
        // true로 설정하면 LiveKit 내부 AudioEngine이 overrideOutputAudioPort(.speaker)를 호출하여
        // 보청기 스트리밍 경로를 강제 해제하고, iOS 시스템 라우팅이 원복을 시도하면서 토글 루프가 발생해
        // 오디오 출력이 완전히 끊깁니다.
        if audioManager.isHearingAidConnected {
            AudioManager.shared.isSpeakerOutputPreferred = false
            logger.info("🔇 Hearing aid detected — forcing isSpeakerOutputPreferred=false to protect MFi routing")
        } else {
            AudioManager.shared.isSpeakerOutputPreferred = audioManager.isSpeakerOverrideActive
        }

        // 4. Activate route monitoring.
        audioManager.configureAndActivate()

        // 4.5. Bluetooth audio route settle delay.
        // When a hearing aid connects, iOS needs time to fully initialize the
        // Bluetooth HFP/A2DP path before AVAudioEngine can start. Attempting
        // AUIOClient_StartIO too quickly results in error -3001 (kAudioEngineErr).
        if audioManager.isHearingAidConnected {
            try? await Task.sleep(for: .milliseconds(800))
        }

        do {
            // 5. Create a fresh Room and wire up the delegate.
            let newRoom = Room(delegate: self)
            self.room = newRoom

            // 6. Retrieve LiveKit connection token (dynamic server vs static configuration)
            let token: String
            if let serverURL = AppConfig.tokenServerURL, !serverURL.isEmpty {
                do {
                    token = try await fetchDynamicToken(from: serverURL)
                    logger.info("✅ Successfully fetched dynamic token from token server")
                } catch {
                    logger.error("❌ Failed to fetch dynamic token: \(error.localizedDescription, privacy: .public). Falling back to static token.")
                    token = AppConfig.livekitToken
                }
            } else {
                token = AppConfig.livekitToken
            }

            // 7. Connect to the LiveKit SFU.
            logger.info("Connecting to LiveKit at \(AppConfig.livekitURL, privacy: .public)…")
            try await newRoom.connect(
                url: AppConfig.livekitURL,
                token: token
            )

            // 8. Publish the local microphone track.
            try await newRoom.localParticipant.setMicrophone(enabled: true)
            logger.info("🎤 Microphone published successfully")

            // 9. Force microphone mute state synchronization immediately after publishing.
            self.updateMicMuteState()

            // 10. Mark as live.
            isConnected = true
            isTranslating = true

            // Send initial mode to backend
            await sendModeChange(mode: appMode)

            logger.info("✅ Translation started — mic enabled, waiting for agent audio")
        } catch {
            logger.error("❌ Failed to start translation: \(error.localizedDescription, privacy: .public)")
            connectionError = error.localizedDescription

            // Clean up partially-initialised state.
            await cleanupRoom()
            audioManager.deactivate()
        }
    }

    /// Disconnects from the LiveKit room and tears down the audio
    /// session.
    ///
    /// Safe to call even when not connected — the method is a
    /// no-op in that case.
    func stopTranslation() async {
        guard isTranslating || room != nil else {
            logger.debug("stopTranslation called while not translating — no-op")
            return
        }

        logger.info("Stopping translation…")

        await cleanupRoom()
        audioManager.deactivate()

        logger.info("Translation stopped")
    }

    // MARK: – Caption Management

    /// Appends or replaces the latest partial caption.
    ///
    /// - If `isPartial` is `true` **and** the last history entry is
    ///   also partial, replace it in-place (smooth streaming UX).
    /// - Otherwise append a brand-new entry.
    /// - Trim history to ``AppConfig/maxCaptionHistory``.
    private func appendCaption(originalText: String, translatedText: String, isPartial: Bool) {
        let entry = CaptionEntry(originalText: originalText, translatedText: translatedText, isPartial: isPartial)

        if isPartial, let last = captionHistory.last, last.isPartial {
            // Replace the trailing partial entry.
            captionHistory[captionHistory.count - 1] = entry
        } else {
            captionHistory.append(entry)
        }

        // Trim oldest entries.
        if captionHistory.count > AppConfig.maxCaptionHistory {
            captionHistory.removeFirst(
                captionHistory.count - AppConfig.maxCaptionHistory
            )
        }

        currentCaption = translatedText
    }

    // MARK: – Internal Helpers

    /// Tears down the room connection and resets published state.
    private func cleanupRoom() async {
        unmuteDebounceTimer?.invalidate()
        unmuteDebounceTimer = nil
        isAISpeakingByVAD = false
        isAISpeakingByState = false

        if let room {
            do {
                try await room.localParticipant.setMicrophone(enabled: false)
            } catch {
                logger.warning("Could not disable mic before disconnect: \(error.localizedDescription, privacy: .public)")
            }
            await room.disconnect()
        }
        room = nil

        isConnected = false
        isTranslating = false
        connectionQuality = .unknown
    }

    /// Fetches a short-lived LiveKit token from the specified token server URL.
    private func fetchDynamicToken(from serverURLString: String) async throws -> String {
        guard let url = URL(string: serverURLString) else {
            throw URLError(.badURL)
        }

        logger.info("Fetching dynamic LiveKit token from server: \(serverURLString, privacy: .public)...")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0 // 8 second timeout for good UX

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct TokenResponse: Codable {
            let token: String
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.token
    }

    // MARK: – App Mode & Exporting

    /// Propagates the current mode to the backend translation agent.
    func sendModeChange(mode: AppMode) async {
        guard isConnected, let room = self.room else {
            logger.debug("Cannot send mode change — not connected to LiveKit room")
            return
        }

        let payload = ["type": "mode_change", "mode": mode.rawValue]
        do {
            let data = try JSONEncoder().encode(payload)
            let options = DataPublishOptions(topic: "mode_change")
            try await room.localParticipant.publish(
                data: data,
                options: options
            )
            logger.info("✅ Propagated mode change to backend: \(mode.rawValue, privacy: .public)")
        } catch {
            logger.error("❌ Failed to send mode change data packet: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Formats the current caption history into a text file and returns a temporary URL for sharing.
    func exportMinutes() -> URL? {
        guard !captionHistory.isEmpty else {
            logger.warning("Attempted to export minutes, but caption history is empty")
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: Date())

        var content = """
        ==================================================
        StarLink 대화 회의록 (\(dateString))
        ==================================================
        
        """

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for entry in captionHistory {
            let timeStr = timeFormatter.string(from: entry.timestamp)
            if appMode == .transcription {
                content += "[\(timeStr)] \(entry.translatedText)\n"
            } else {
                if !entry.originalText.isEmpty {
                    content += "[\(timeStr)] (원문) \(entry.originalText)\n"
                }
                content += "[\(timeStr)] (번역) \(entry.translatedText)\n"
            }
            content += "\n"
        }

        content += "==================================================\n"

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "StarLink_Minutes_\(UUID().uuidString.prefix(6)).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.info("✅ Minutes successfully written to: \(fileURL.path, privacy: .public)")
            return fileURL
        } catch {
            logger.error("❌ Failed to write exported minutes: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Clears the rolling caption history and current active caption.
    func clearHistory() {
        captionHistory.removeAll()
        currentCaption = ""
        logger.info("🗑️ Caption history cleared by user request")
    }
}

// MARK: - RoomDelegate

extension LiveKitStreamManager: RoomDelegate {

    /// Fires whenever the room's transport state changes.
    nonisolated func room(
        _ room: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from oldConnectionState: ConnectionState
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            logger.info(
                "Connection state: \(String(describing: oldConnectionState)) → \(String(describing: connectionState))"
            )

            switch connectionState {
            case .connected:
                isConnected = true
                logger.info("Connected to room. Propagating initial app mode...")
                Task {
                    await self.sendModeChange(mode: self.appMode)
                }
            case .disconnected:
                isConnected = false
            default:
                break
            }
        }
    }

    /// Fires when the room is disconnected (possibly with an error).
    nonisolated func room(
        _ room: Room,
        didDisconnectWithError error: LiveKitError?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let error {
                logger.error("Room disconnected with error: \(error.localizedDescription, privacy: .public)")
                connectionError = error.localizedDescription
            } else {
                logger.info("Room disconnected gracefully")
            }

            isConnected = false
            isTranslating = false
            connectionQuality = .unknown
            self.room = nil

            audioManager.deactivate()
        }
    }

    /// Fires when a remote participant's track is subscribed.
    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant,
        didSubscribeTrack publication: RemoteTrackPublication
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let kind = publication.track?.kind ?? .none
            logger.info("Subscribed to track \(publication.sid, privacy: .public) (kind: \(String(describing: kind))) from participant \(participant.identity?.stringValue ?? "unknown", privacy: .public)")

            if kind == .audio {
                self.logger.info("🔊 Remote audio track subscribed — LiveKit will auto-play to current output device")
            }
        }
    }

    /// Fires when a remote participant's track is unsubscribed.
    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant,
        didUnsubscribeTrack publication: RemoteTrackPublication
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            logger.info("Unsubscribed from track \(publication.sid, privacy: .public) from participant \(participant.identity?.stringValue ?? "unknown", privacy: .public)")
        }
    }

    /// Fires when a participant's connection quality changes.
    nonisolated func room(
        _ room: Room,
        participant: Participant,
        didUpdateConnectionQuality quality: ConnectionQuality
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Only track remote participant (agent) quality, or
            // the local participant if no remote is present yet.
            connectionQuality = quality

            logger.debug("Connection quality for \(participant.identity?.stringValue ?? "unknown", privacy: .public): \(String(describing: quality))")
        }
    }

    /// Fires when a data packet arrives over the LiveKit data
    /// channel.  The translation agent sends caption text as
    /// raw UTF-8 bytes or structured JSON.
    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType: EncryptionType
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if topic == "caption" {
                struct SegmentPayload: Codable {
                    let id: String
                    let original: String
                    let translated: String
                    let isPartial: Bool
                    let language: String?
                }

                struct CaptionPayload: Codable {
                    let segments: [SegmentPayload]
                }

                do {
                    let payload = try JSONDecoder().decode(CaptionPayload.self, from: data)
                    logger.debug("Decoded caption payload containing \(payload.segments.count, privacy: .public) segments")
                    for segment in payload.segments {
                        self.updateOrAppendCaption(
                            idString: segment.id,
                            originalText: segment.original,
                            translatedText: segment.translated,
                            isPartial: segment.isPartial,
                            language: segment.language
                        )
                    }
                } catch {
                    logger.error("Failed to decode caption JSON: \(error.localizedDescription, privacy: .public)")
                }
            } else if topic == "audio_state" {
                struct AudioStatePayload: Codable {
                    let type: String
                    let state: String
                }
                do {
                    let payload = try JSONDecoder().decode(AudioStatePayload.self, from: data)
                    logger.info("Received audio state: \(payload.state, privacy: .public)")
                    self.handleAudioStateChange(state: payload.state)
                } catch {
                    logger.error("Failed to decode audio state: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                guard let text = String(data: data, encoding: .utf8),
                      !text.isEmpty else {
                    logger.warning("Received empty or non-UTF8 data packet — ignoring")
                    return
                }

                // Convention: topic "partial" → streaming segment,
                //             anything else  → final caption.
                let isPartial = (topic == "partial")

                logger.debug("Caption (\(isPartial ? "partial" : "final", privacy: .public)): \(text, privacy: .public)")
                self.appendCaption(originalText: "", translatedText: text, isPartial: isPartial)
            }
        }
    }

    /// Updates an existing caption segment by ID, or appends a new one.
    private func updateOrAppendCaption(idString: String, originalText: String, translatedText: String, isPartial: Bool, language: String? = nil) {
        // Find if an entry with the same id exists
        if let index = captionHistory.firstIndex(where: { $0.id == idString }) {
            // Update existing entry (preserves the original timestamp)
            captionHistory[index] = CaptionEntry(
                originalText: originalText,
                translatedText: translatedText,
                isPartial: isPartial,
                language: language ?? captionHistory[index].language,
                id: idString,
                timestamp: captionHistory[index].timestamp
            )
        } else {
            // Append new entry
            let entry = CaptionEntry(
                originalText: originalText,
                translatedText: translatedText,
                isPartial: isPartial,
                language: language,
                id: idString
            )
            captionHistory.append(entry)
        }

        // Trim oldest entries
        if captionHistory.count > AppConfig.maxCaptionHistory {
            captionHistory.removeFirst(
                captionHistory.count - AppConfig.maxCaptionHistory
            )
        }

        currentCaption = translatedText
    }

    private func handleAudioStateChange(state: String) {
        isAISpeakingByState = (state == "playing")
        logger.info("Audio state changed from backend: \(state, privacy: .public) -> isAISpeakingByState = \(self.isAISpeakingByState, privacy: .public)")
        updateMicMuteState()
    }

    private func updateMicMuteState() {
        // ⚠️ [deadlock 해제] 백엔드 상태(isAISpeakingByState) 대신 실제 물리적인 오디오 송출 여부(isAISpeakingByVAD)만 기준으로 마이크를 음소거합니다.
        // 세션 시작 시 백엔드가 준비 단계에서 플레이 상태를 임의 전송하여 마이크가 영구 음소거되는 현상을 방지합니다.
        let shouldMute = isAISpeakingByVAD

        if shouldMute {
            // AI가 말하기 시작하면 즉시 타이머를 해제하고 마이크를 음소거합니다.
            unmuteDebounceTimer?.invalidate()
            unmuteDebounceTimer = nil

            logger.info("🔊 AI is speaking (VAD). Muting local microphone track immediately...")
            setMicMuted(true)
        } else {
            // AI가 발화를 마쳤을 때 즉시 켜지 않고 500ms 지연을 두어 재생 잔향 에코를 차단합니다.
            unmuteDebounceTimer?.invalidate()
            unmuteDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // ⚠️ [중요] 타이머가 실행되는 물리적 찰나에 AI가 다시 말하기 시작했다면 언뮤트를 전면 취소
                    guard !self.isAISpeakingByVAD else {
                        self.logger.info("⚠️ Timer fired but AI started speaking again. Aborting unmute.")
                        return
                    }
                    self.logger.info("🎤 Safe silence buffer passed. Unmuting local microphone track...")
                    self.setMicMuted(false)
                }
            }
        }
    }

    private func setMicMuted(_ muted: Bool) {
        // ⚠️ [WebRTC 하드웨어 락 방지]
        // WebRTC SDK 고유의 버그로 인해 LocalAudioTrack을 물리적으로 mute/unmute 할 때 
        // 오디오 디바이스 세션이 재배치되면서 원격 재생 오디오(보청기/스피커)가 뚝 끊기거나 재생이 완전히 먹통이 됩니다.
        // 에코 피드백 루프는 Gemini Live API의 지시문(Ignore Self-Feedback)에 의해 완벽하게 필터링되므로,
        // 클라이언트 단의 무리한 물리 마이크 트랙 락을 차단합니다.
        self.logger.info("ℹ️ Skip physical mic mute state change to \(muted) to keep audio output alive")
    }

    /// Fires when a participant starts or stops speaking.
    nonisolated func room(
        _ room: Room,
        participant: Participant,
        didUpdateIsSpeaking isSpeaking: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Only care about remote participants (the translation agent)
            guard participant is RemoteParticipant else { return }

            self.isAISpeakingByVAD = isSpeaking
            self.logger.info("Participant \(participant.identity?.stringValue ?? "unknown", privacy: .public) speaking status updated: \(isSpeaking) -> isAISpeakingByVAD = \(isSpeaking)")
            self.updateMicMuteState()
        }
    }
}
