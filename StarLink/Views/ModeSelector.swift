// ModeSelector.swift
// StarLink — Premium Hearing Aid Translation
//
// A capsule-styled glassmorphic segment selector to toggle between
// translation and transcription (minutes) modes. Built with smooth
// micro-animations and haptic feedback.

import SwiftUI
import UIKit

struct ModeSelector: View {

    @EnvironmentObject var streamManager: LiveKitStreamManager

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Translation Mode Tab
            tabButton(
                mode: .translation,
                title: "통역 모드",
                icon: "character.bubble.fill"
            )

            // MARK: - Transcription Mode Tab
            tabButton(
                mode: .transcription,
                title: "기록 모드 (회의록)",
                icon: "doc.text.fill"
            )
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("앱 모드 선택기")
    }

    // MARK: - Tab Button Helper

    private func tabButton(mode: AppMode, title: String, icon: String) -> some View {
        let isActive = streamManager.appMode == mode

        return Button {
            selectMode(mode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? Color.white : Theme.textSecondary)

                Text(title)
                    .font(.system(size: 13, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? Color.white : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Theme.accentBlue,
                                        Theme.accentBlue.opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .matchedGeometryEffect(id: "activeTabBackground", in: animationNamespace)
                            .shadow(color: Theme.accentBlue.opacity(0.35), radius: 8, y: 2)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(title) 탭")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Actions & Namespace

    @Namespace private var animationNamespace

    private func selectMode(_ mode: AppMode) {
        guard streamManager.appMode != mode else { return }

        // Trigger light haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            streamManager.appMode = mode
        }
    }
}
