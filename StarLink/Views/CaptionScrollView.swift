// CaptionScrollView.swift
// StarLink — Premium Hearing Aid Translation
//
// Real-time caption display area with auto-scrolling, glassmorphic
// container, and animated entry transitions.

import SwiftUI

struct CaptionScrollView: View {

    @EnvironmentObject var streamManager: LiveKitStreamManager
    @State private var showHistorySheet = false

    /// Formatter for caption timestamps.
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    var body: some View {
        ZStack {
            // Glassmorphic container
            containerBackground

            // Content
            if streamManager.captionHistory.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Top Bar for Action Buttons & Status Badge
                    HStack(alignment: .center) {
                        // 좌측: 언어 배지 & 번역중 상태 표시
                        if let lastEntry = streamManager.captionHistory.last {
                            HStack(spacing: 8) {
                                if let lang = lastEntry.language, !lang.isEmpty, lang.lowercased() != "unknown" {
                                    let langText: String = {
                                        switch lang.lowercased() {
                                        case "en": return "영어"
                                        case "ja": return "일본어"
                                        case "zh": return "중국어"
                                        case "ko": return "한국어"
                                        default: return lang.uppercased()
                                        }
                                    }()
                                    
                                    Text(langText)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.accentBlue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(Theme.accentBlue.opacity(0.12))
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Theme.accentBlue.opacity(0.25), lineWidth: 0.5)
                                                )
                                        )
                                }
                                
                                if lastEntry.isPartial {
                                    Circle()
                                        .fill(Theme.accentBlue)
                                        .frame(width: 6, height: 6)
                                        .symbolEffect(.pulse, isActive: true)
                                    Text(streamManager.appMode == .transcription ? "기록 중..." : "번역 중...")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.accentBlue)
                                }
                            }
                            .transition(.opacity)
                        }

                        Spacer()
                        
                        HStack(spacing: 8) {
                            // 회의록 공유 버튼
                            Button {
                                shareMinutes()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("회의록 공유")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.accentBlue.opacity(0.15))
                                .foregroundStyle(Theme.accentBlue)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Theme.accentBlue.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .accessibilityLabel("회의록 공유 버튼")
                            .accessibilityHint("이중 탭하여 대화 기록을 텍스트 파일로 내보냅니다")

                            // Floating "전체 기록" history button
                            Button {
                                showHistorySheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("전체 기록")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.accentBlue.opacity(0.15))
                                .foregroundStyle(Theme.accentBlue)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Theme.accentBlue.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .padding(.horizontal, 16)
                    .frame(height: 44)

                    // 스크롤뷰 영역
                    captionList
                        .clipped()
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("실시간 자막 영역")
        .sheet(isPresented: $showHistorySheet) {
            FullHistoryView(history: streamManager.captionHistory)
                .environmentObject(streamManager)
        }
    }

    // MARK: - Actions

    private func shareMinutes() {
        guard let fileURL = streamManager.exportMinutes() else { return }

        // Find active window scene to present UIActivityViewController
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {

            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

            // iPad support
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Caption List

    // MARK: - Caption List

    private var captionList: some View {
        let displayHistory = Array(streamManager.captionHistory.suffix(2))
        
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 28) {
                    ForEach(displayHistory) { entry in
                        let isLast = entry.id == displayHistory.last?.id
                        
                        LyricsCaptionCard(entry: entry, isHighlighted: isLast)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: streamManager.captionHistory.count) { _ in
                if let lastId = displayHistory.last?.id {
                    withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamManager.currentCaption) { _ in
                if let lastId = displayHistory.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onAppear {
                if let lastId = displayHistory.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let isTranscription = streamManager.appMode == .transcription

        return VStack(spacing: 12) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .symbolEffect(.pulse, isActive: true)

            Text(isTranscription ? "한국어 기록 대기 중..." : "번역 대기 중...")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .phaseAnimator([false, true]) { content, phase in
                    content.opacity(phase ? 0.4 : 0.9)
                } animation: { _ in
                    .easeInOut(duration: 1.8)
                }

            Text(isTranscription ? "아래 버튼을 눌러 실시간 자막을 시작하세요" : "아래 버튼을 눌러 번역을 시작하세요")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(isTranscription ? "한국어 기록 대기 중. 아래 버튼을 눌러 실시간 자막을 시작하세요." : "번역 대기 중. 아래 버튼을 눌러 번역을 시작하세요.")
    }

    // MARK: - Backgrounds & Masks

    /// Glassmorphic rounded container.
    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.surface)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

// MARK: - Lyrics Caption Card

private struct LyricsCaptionCard: View {
    @EnvironmentObject var streamManager: LiveKitStreamManager
    let entry: CaptionEntry
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Original Script (English / Japanese / Chinese)
            if streamManager.appMode == .translation && !entry.originalText.isEmpty {
                Text(entry.originalText)
                    .font(.system(size: isHighlighted ? 15 : 13, weight: isHighlighted ? .medium : .regular, design: .rounded))
                    .foregroundStyle(isHighlighted ? Theme.textSecondary : Theme.textTertiary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }
            
            // Translated / Transcribed Korean Script
            if !entry.translatedText.isEmpty {
                Text(entry.translatedText)
                    .font(.system(size: isHighlighted ? 22 : 16, weight: isHighlighted ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isHighlighted ? Theme.textPrimary : Theme.textSecondary.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
            } else if isHighlighted && entry.isPartial {
                HStack(spacing: 8) {
                    Text(streamManager.appMode == .transcription ? "음성을 인식하는 중" : "번역을 생성하는 중")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isHighlighted ? 12 : 6)
        .opacity(isHighlighted ? 1.0 : 0.45)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.65, dampingFraction: 0.85), value: isHighlighted)
    }
}

// MARK: - Full History View

/// A modal sheet presenting the complete translation history with timestamps.
struct FullHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var streamManager: LiveKitStreamManager
    let history: [CaptionEntry]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(history) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(timeString(from: entry.timestamp))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)

                                if !entry.originalText.isEmpty {
                                    Text(entry.originalText)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineSpacing(3)
                                }

                                if !entry.translatedText.isEmpty {
                                    Text(entry.translatedText)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineSpacing(4)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("전체 대화 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("초기화", role: .destructive) {
                        streamManager.clearHistory()
                        dismiss()
                    }
                    .foregroundStyle(Theme.errorRed)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accentBlue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func timeString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}
