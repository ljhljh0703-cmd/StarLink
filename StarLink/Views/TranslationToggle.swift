// TranslationToggle.swift
// StarLink — Premium Hearing Aid Translation
//
// Hero interaction element — a large circular toggle button with
// concentric pulse rings, haptic feedback, and state-driven animations.

import SwiftUI
import UIKit

struct TranslationToggle: View {

    @EnvironmentObject var audioManager: MFiAudioManager
    @EnvironmentObject var streamManager: LiveKitStreamManager

    /// Guards against rapid double-taps during async state transitions.
    @State private var isProcessing = false

    /// Drives the concentric pulse ring expansion.
    @State private var pulsePhase: CGFloat = 0

    /// Button size constant.
    private let buttonSize: CGFloat = 160

    var body: some View {
        VStack(spacing: 20) {
            // MARK: Main Toggle Button
            toggleButton

            // MARK: Language Indicator
            if streamManager.appMode == .translation {
                languageIndicator
            } else {
                transcriptionIndicator
            }

            // MARK: Error Display
            errorDisplay
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Toggle Button

    private var toggleButton: some View {
        ZStack {
            // Concentric pulse rings (active state only)
            if streamManager.isTranslating {
                pulseRings
            }

            // Main button circle
            mainCircle
        }
        .frame(width: buttonSize + 60, height: buttonSize + 60)
    }

    /// Expanding concentric rings that radiate outward when translating.
    private var pulseRings: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = buttonSize / 2
                let now = timeline.date.timeIntervalSinceReferenceDate
                let ringCount = 3

                for i in 0..<ringCount {
                    let offset = Double(i) / Double(ringCount)
                    let progress = (now.truncatingRemainder(dividingBy: 2.0) / 2.0 + offset)
                        .truncatingRemainder(dividingBy: 1.0)

                    let radius = baseRadius + CGFloat(progress) * 50
                    let opacity = 1.0 - progress

                    let path = Circle()
                        .path(in: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        ))

                    context.stroke(
                        path,
                        with: .color(Theme.successGreen.opacity(opacity * 0.4)),
                        lineWidth: 2
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// The main circular button with icon and label.
    private var mainCircle: some View {
        Button {
            handleToggle()
        } label: {
            ZStack {
                // Background circle
                Circle()
                    .fill(circleBackground)
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle()
                            .stroke(circleBorder, lineWidth: 2.5)
                    )
                    .shadow(
                        color: streamManager.isTranslating
                            ? Theme.successGreen.opacity(0.35)
                            : Theme.accentBlue.opacity(0.2),
                        radius: 20
                    )

                // Icon + Label
                VStack(spacing: 10) {
                    Image(systemName: streamManager.isTranslating ? "waveform" : "mic.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(
                            streamManager.isTranslating
                                ? Color.white
                                : Theme.accentBlue
                        )
                        .symbolEffect(.variableColor, isActive: streamManager.isTranslating)
                        .contentTransition(.symbolEffect(.replace))

                    let isTrans = streamManager.appMode == .transcription
                    let activeText = isTrans ? "기록 중..." : "번역 중..."
                    let idleText = isTrans ? "기록 시작" : "번역 시작"

                    Text(streamManager.isTranslating ? activeText : idleText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            streamManager.isTranslating
                                ? Color.white.opacity(0.9)
                                : Theme.textSecondary
                        )
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.6 : 1.0)
        .accessibilityLabel(
            streamManager.isTranslating
                ? (streamManager.appMode == .transcription ? "기록 중지 버튼. 현재 실시간 자막 기록이 진행 중입니다." : "번역 중지 버튼. 현재 번역이 진행 중입니다.")
                : (streamManager.appMode == .transcription ? "기록 시작 버튼. 탭하여 실시간 한국어 자막 기록을 시작합니다." : "번역 시작 버튼. 탭하여 실시간 번역을 시작합니다.")
        )
        .accessibilityHint(
            streamManager.isTranslating
                ? (streamManager.appMode == .transcription ? "이중 탭하여 기록을 중지합니다" : "이중 탭하여 번역을 중지합니다")
                : (streamManager.appMode == .transcription ? "이중 탭하여 기록을 시작합니다" : "이중 탭하여 번역을 시작합니다")
        )
    }

    // MARK: - Language Indicator

    private var languageIndicator: some View {
        HStack(spacing: 6) {
            Text("EN / JA / ZH")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.accentBlue.opacity(0.6))

            Text("🇰🇷 KO")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityLabel("지원 언어: 영어, 일본어, 중국어를 한국어로 번역")
    }

    // MARK: - Transcription Indicator

    private var transcriptionIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "hearingdevice.ear")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accentBlue.opacity(0.8))
            Text("실시간 한국어 자막 (STT)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityLabel("한국어 실시간 음성 자막 기록 활성화됨")
    }

    // MARK: - Error Display

    @ViewBuilder
    private var errorDisplay: some View {
        if let error = streamManager.connectionError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.errorRed)

                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.errorRed)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.errorRed.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.errorRed.opacity(0.3), lineWidth: 1)
                    )
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityLabel("오류: \(error)")
        }
    }

    // MARK: - Computed Styles

    private var circleBackground: some ShapeStyle {
        if streamManager.isTranslating {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Theme.successGreen,
                        Theme.successGreen.opacity(0.75)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Theme.surface)
        }
    }

    private var circleBorder: some ShapeStyle {
        if streamManager.isTranslating {
            return AnyShapeStyle(Theme.successGreen.opacity(0.6))
        } else {
            return AnyShapeStyle(Theme.accentBlue.opacity(0.5))
        }
    }

    // MARK: - Actions

    private func handleToggle() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        guard !isProcessing else { return }

        withAnimation(Theme.springResponse) {
            isProcessing = true
        }

        Task {
            if streamManager.isTranslating {
                await streamManager.stopTranslation()
            } else {
                await streamManager.startTranslation()
            }

            await MainActor.run {
                withAnimation(Theme.springResponse) {
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Scale Button Style

/// Custom button style that provides a subtle scale-down press effect.
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
