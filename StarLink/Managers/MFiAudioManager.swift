// MARK: - MFiAudioManager.swift
// StarLink — Gemini Live Hearing Aid Translation
//
// Owns the AVAudioSession lifecycle and monitors MFi hearing-aid
// connectivity via route-change / interruption notifications.
//
// Design notes
// ─────────────
// • `@MainActor` because every `@Published` property drives SwiftUI.
// • Route-change handling is debounced (0.5 s) to avoid rapid-fire
//   updates when the system toggles routes during BT negotiation.
// • All logging uses `os.Logger` for privacy-safe structured logs
//   that stream to Console.app during development.
// ──────────────────────────────────────────────────────────────────

import AVFoundation
import Combine
import LiveKit
import LiveKitWebRTC
import os

/// Manages the shared `AVAudioSession` for MFi hearing-aid routing.
///
/// Responsibilities:
/// 1. Configure the session for simultaneous capture + playback
///    with optimal hearing-aid routing.
/// 2. Monitor Bluetooth LE / MFi hearing-aid attachment and update
///    observable state so the UI can reflect connectivity.
/// 3. Handle interruptions (phone calls, Siri) and media-service
///    resets gracefully.
@MainActor
final class MFiAudioManager: ObservableObject {

    // MARK: – Published State

    /// `true` when at least one MFi hearing-aid or BLE audio output
    /// is detected on the current audio route.
    @Published private(set) var isHearingAidConnected: Bool = false

    /// Human-readable name of the active output port, e.g.
    /// "Starkey Genesis AI" or "iPhone Speaker".
    @Published private(set) var currentOutputDevice: String = "Unknown"

    /// `true` after ``configureAndActivate()`` succeeds and until
    /// ``deactivate()`` is called.
    @Published private(set) var isSessionActive: Bool = false

    /// `true` when the user has forced the audio output to the built-in speaker.
    @Published private(set) var isSpeakerOverrideActive: Bool = false

    /// Phase-2 prep: mixing slider between translated audio (1.0)
    /// and ambient pass-through (0.0).  Currently unused by the
    /// audio graph but exposed for the UI toggle.
    @Published var mixingRatio: Float = 1.0

    // MARK: – Private

    private let logger = Logger(
        subsystem: "com.starlink.audio",
        category: "MFiAudioManager"
    )

    /// Debounce token for route-change handling.
    private var routeChangeWorkItem: DispatchWorkItem?

    /// Tracks whether an interruption is currently active so we can
    /// decide whether to auto-resume.
    private var isInterrupted: Bool = false

    // MARK: – Lifecycle

    nonisolated init() {
        // Observers are set up on first access from the main actor
        // via `setupNotificationObservers()`.  We defer to avoid
        // capturing `self` before init completes.
        Task { @MainActor [weak self] in
            self?.setupNotificationObservers()
            self?.updateRouteInfo()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: – Public API

    /// Configures and activates the audio session for hearing-aid
    /// streaming with mic capture.
    ///
    /// Category: `.playAndRecord` — enables simultaneous capture
    /// and playback.
    /// Mode: `.voiceChat` — engages echo-cancellation and optimises
    /// the route selector for hearing aids.
    /// Options:
    /// - `.allowBluetoothA2DP` — allows high-quality stereo
    ///   streaming to hearing aids that support A2DP.
    /// - `.defaultToSpeaker` — fallback when no hearing aid is
    ///   connected so the user still hears translated audio.
    func configureAndActivate() {
        // 모든 오디오 세션의 활성화 및 수명주기는 LiveKit SDK의 AudioManager에 위임합니다.
        // MFiAudioManager는 오디오 경로 변화 관찰 및 UI 갱신 상태 관리만 수행합니다.
        isSessionActive = true
        updateRouteInfo()
        logger.info("✅ MFiAudioManager activated monitoring route")
    }

    /// Toggles whether audio is forced to the built-in speaker.
    func toggleSpeakerOverride() {
        let targetOverride = !isSpeakerOverrideActive
        
        // ⚠️ [보청기 라우팅 보호] 보청기 연결 중에 스피커 오버라이드를 켜면
        // LiveKit AudioEngine ↔ iOS 시스템 라우팅 간 토글 루프가 발생하여 오디오가 끊깁니다.
        if targetOverride && isHearingAidConnected {
            logger.warning("⚠️ Speaker override blocked — hearing aid is connected. Forcing speaker would disrupt MFi audio streaming.")
            return
        }
        
        // LiveKit의 AudioManager를 사용하여 스피커 출력을 제어합니다.
        // 수동 overrideOutputAudioPort 호출은 LiveKit의 자동 세션 관리자에 의해 덮어씌워지므로
        // LiveKit API를 통해 스피커 우선 여부를 설정해야 안정적으로 출력 경로가 변경됩니다.
        LiveKit.AudioManager.shared.isSpeakerOutputPreferred = targetOverride
        logger.info("Speaker override changed: \(targetOverride) (via LiveKit AudioManager)")

        isSpeakerOverrideActive = targetOverride
        updateRouteInfo()
    }

    /// Deactivates the audio session, allowing other apps to resume
    /// their audio.
    func deactivate() {
        isSessionActive = false
        logger.info("MFiAudioManager deactivated monitoring")
    }

    // MARK: – Notification Observers

    private func setupNotificationObservers() {
        let nc = NotificationCenter.default

        nc.addObserver(
            self,
            selector: #selector(handleRouteChangeNotification(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(handleInterruptionNotification(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(handleMediaServicesResetNotification(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    // MARK: – Route Change Handling (Debounced)

    @objc
    nonisolated private func handleRouteChangeNotification(
        _ notification: Notification
    ) {
        Task { @MainActor [weak self] in
            self?.handleRouteChange(notification: notification)
        }
    }

    private func handleRouteChange(notification: Notification) {
        // Cancel any pending debounced work.
        routeChangeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.processRouteChange(notification: notification)
            }
        }
        routeChangeWorkItem = workItem

        // Debounce by 0.5 s to ride out rapid BT negotiation flips.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.5,
            execute: workItem
        )
    }

    private func processRouteChange(notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            updateRouteInfo()
            return
        }

        switch reason {
        case .newDeviceAvailable:
            logger.info("New audio device available")
            // A new wireless device/headset was connected. Reset speaker override to prioritize the new route.
            if isSpeakerOverrideActive {
                logger.info("Resetting speaker override due to new device connection")
                isSpeakerOverrideActive = false
                do {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                } catch {
                    logger.error("Failed to reset speaker override: \(error.localizedDescription, privacy: .public)")
                }
            }
            updateRouteInfo()

            if isHearingAidConnected {
                logger.info("✅ Wireless audio device connected: \(self.currentOutputDevice, privacy: .public)")
            }

        case .oldDeviceUnavailable:
            let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription

            let lostHearingAid = previousRoute?.outputs.contains { port in
                Self.hearingAidPortTypes.contains(port.portType)
            } ?? false

            updateRouteInfo()

            if lostHearingAid {
                logger.warning("⚠️ MFi hearing aid disconnected — fell back to: \(self.currentOutputDevice, privacy: .public)")
            }

        case .categoryChange:
            logger.debug("Audio category changed")
            updateRouteInfo()

        case .unknown, .override, .routeConfigurationChange, .wakeFromSleep,
             .noSuitableRouteForCategory:
            updateRouteInfo()

        @unknown default:
            logger.debug("Unknown route change reason: \(reasonValue)")
            updateRouteInfo()
        }
    }

    // MARK: – Interruption Handling

    @objc
    nonisolated private func handleInterruptionNotification(
        _ notification: Notification
    ) {
        Task { @MainActor [weak self] in
            self?.handleInterruption(notification: notification)
        }
    }

    private func handleInterruption(notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            isInterrupted = true
            logger.info("Audio session interrupted")

        case .ended:
            isInterrupted = false

            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) {
                logger.info("Interruption ended — resuming audio session")
                configureAndActivate()
            } else {
                logger.info("Interruption ended — not resuming (system did not request)")
            }

        @unknown default:
            logger.debug("Unknown interruption type")
        }
    }

    // MARK: – Media Services Reset

    @objc
    nonisolated private func handleMediaServicesResetNotification(
        _ notification: Notification
    ) {
        Task { @MainActor [weak self] in
            self?.handleMediaServicesReset(notification: notification)
        }
    }

    private func handleMediaServicesReset(notification: Notification) {
        logger.warning("⚠️ Media services were reset — performing full teardown and reconfigure")

        // Full teardown: clear all state.
        isSessionActive = false
        isSpeakerOverrideActive = false
        isHearingAidConnected = false
        currentOutputDevice = "Unknown"
        isInterrupted = false
        routeChangeWorkItem?.cancel()
        routeChangeWorkItem = nil

        // Re-register observers (they may have been invalidated).
        NotificationCenter.default.removeObserver(self)
        setupNotificationObservers()

        // Re-activate if we were previously active.
        configureAndActivate()
    }

    // MARK: – Route Inspection

    /// Port types that indicate a hearing-aid or hearing-aid-
    /// compatible Bluetooth accessory.
    private static let hearingAidPortTypes: Set<AVAudioSession.Port> = [
        AVAudioSession.Port(rawValue: "HearingAppliance"),
        .bluetoothLE,
        .bluetoothA2DP,
        .bluetoothHFP
    ]

    /// Scans the active audio route and updates all published
    /// properties.
    private func updateRouteInfo() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        let hearingAidPort = outputs.first { port in
            Self.hearingAidPortTypes.contains(port.portType)
        }

        #if targetEnvironment(simulator)
        isHearingAidConnected = true
        #else
        isHearingAidConnected = hearingAidPort != nil
        #endif

        if let primaryOutput = outputs.first {
            currentOutputDevice = primaryOutput.portName
        } else {
            currentOutputDevice = "No Output"
        }

        logger.debug(
            "Route updated — device: \(self.currentOutputDevice, privacy: .public), hearingAid: \(self.isHearingAidConnected)"
        )
    }
}
