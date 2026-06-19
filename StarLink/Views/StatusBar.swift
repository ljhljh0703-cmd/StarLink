// StatusBar.swift
// StarLink — Premium Hearing Aid Translation
//
// Top status section displaying the app brand, connection status,
// and hearing aid device information with glassmorphic styling.

import SwiftUI
import AVKit

struct StatusBar: View {

    @EnvironmentObject var audioManager: MFiAudioManager
    @EnvironmentObject var streamManager: LiveKitStreamManager
    @Binding var showSettings: Bool

    /// Controls the pulsing dot animation when connected.
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 14) {
            // MARK: Brand Title
            brandTitle

            Spacer()

            // MARK: Connection Indicator
            connectionDot

            // MARK: Device Info
            deviceInfo

            // MARK: Speaker Override Button
            Button {
                audioManager.toggleSpeakerOverride()
            } label: {
                Image(systemName: audioManager.isSpeakerOverrideActive ? "speaker.wave.3.fill" : "speaker.wave.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(audioManager.isSpeakerOverrideActive ? Theme.successGreen : Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(audioManager.isSpeakerOverrideActive ? Theme.successGreen.opacity(0.15) : Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(audioManager.isSpeakerOverrideActive ? Theme.successGreen.opacity(0.3) : Theme.border, lineWidth: 1)
                            )
                    )
            }
            .accessibilityLabel(audioManager.isSpeakerOverrideActive ? "iPhone 스피커 강제 출력 활성화됨" : "일반 오디오 경로 출력 중")

            // MARK: Audio Route Picker Button
            AudioRoutePicker()
                .frame(width: 32, height: 32)

            // MARK: Settings Button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    )
            }
            .accessibilityLabel("연결 설정 버튼")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10) // Slightly adjusted padding for the AirPlay button
        .background(statusBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Sub-views

    /// Gradient-styled app name.
    private var brandTitle: some View {
        Text("StarLink")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.titleGradient)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }

    /// Animated status dot — green + pulsing when connected, gray when not.
    private var connectionDot: some View {
        ZStack {
            // Outer pulse ring (visible only when connected)
            if streamManager.isConnected {
                Circle()
                    .fill(Theme.successGreen.opacity(0.3))
                    .frame(width: 18, height: 18)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            // Core dot
            Circle()
                .fill(streamManager.isConnected ? Theme.successGreen : Theme.textTertiary)
                .frame(width: 10, height: 10)
                .shadow(
                    color: streamManager.isConnected ? Theme.successGreen.opacity(0.6) : .clear,
                    radius: 4
                )
        }
        .frame(width: 20, height: 20)
        .onAppear { isPulsing = true }
        .onChange(of: streamManager.isConnected) { _, connected in
            isPulsing = connected
        }
    }

    /// Hearing aid icon + device name or warning.
    private var deviceInfo: some View {
        HStack(spacing: 6) {
            Image(systemName: isWirelessDevice ? "headphones" : "speaker.wave.2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isWirelessDevice ? Theme.successGreen : Theme.textSecondary)
                .symbolEffect(
                    .pulse,
                    isActive: isWirelessDevice
                )

            Text(friendlyDeviceName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isWirelessDevice ? Theme.successGreen : Theme.textSecondary)
                .lineLimit(1)
        }
        .accessibilityLabel("오디오 출력 장치: \(friendlyDeviceName)")
    }

    private var isWirelessDevice: Bool {
        audioManager.isHearingAidConnected
    }

    private var friendlyDeviceName: String {
        let device = audioManager.currentOutputDevice
        if device == "Speaker" || device == "Receiver" || device == "No Output" || device == "Unknown" {
            return "iPhone 스피커"
        }
        return device
    }

    /// Glassmorphic container background.
    private var statusBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let connection = streamManager.isConnected ? "서버 연결됨" : "서버 연결 안 됨"
        let device = "오디오 출력: \(friendlyDeviceName)"
        let override = audioManager.isSpeakerOverrideActive ? "(스피커 강제 출력 중)" : ""
        return "StarLink 상태. \(connection). \(device) \(override)"
    }
}

// MARK: - Audio Route Picker

/// SwiftUI wrapper for UIKit's AVRoutePickerView (AirPlay routing menu)
struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        // Stylize the route picker to match our dark theme
        picker.activeTintColor = UIColor(red: 0.31, green: 0.55, blue: 1.0, alpha: 1.0) // Theme.accentBlue
        picker.tintColor = .white
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
