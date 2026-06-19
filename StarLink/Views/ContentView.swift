// ContentView.swift
// StarLink — Premium Hearing Aid Translation
//
// Main compositor view that assembles the full-screen UI.
// Manages the dark gradient background, layout of StatusBar,
// CaptionScrollView, and TranslationToggle.

import SwiftUI

// MARK: - Design System

/// Centralised theme tokens for the StarLink design language.
/// All colours conform to WCAG AAA contrast against the dark background.
enum Theme {

    // MARK: Background

    static let backgroundTop    = Color(red: 0.039, green: 0.039, blue: 0.059)   // #0A0A0F
    static let backgroundBottom = Color(red: 0.078, green: 0.078, blue: 0.157)   // #141428

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Accent Colours

    /// Primary electric blue — links, active controls, brand identity.
    static let accentBlue  = Color(red: 0.31, green: 0.55, blue: 1.0)           // #4F8CFF

    /// Success / active state green.
    static let successGreen = Color(red: 0.2, green: 0.84, blue: 0.5)            // #33D680

    /// Error / destructive red.
    static let errorRed     = Color(red: 1.0, green: 0.35, blue: 0.35)           // #FF5959

    /// Warning orange — used for disconnection notices.
    static let warningOrange = Color(red: 1.0, green: 0.65, blue: 0.25)          // #FFA640

    // MARK: Surfaces & Text

    /// Elevated card / container fill.
    static let surface      = Color.white.opacity(0.06)

    /// Subtle border for glassmorphic containers.
    static let border       = Color.white.opacity(0.1)

    /// Primary text — pure white for maximum contrast on dark bg.
    static let textPrimary  = Color.white

    /// Secondary text — slightly dimmed.
    static let textSecondary = Color.white.opacity(0.55)

    /// Tertiary text — timestamps, hints.
    static let textTertiary  = Color.white.opacity(0.35)

    // MARK: Typography Helpers

    /// Title gradient for the app name.
    static var titleGradient: LinearGradient {
        LinearGradient(
            colors: [accentBlue, Color(red: 0.3, green: 0.82, blue: 0.95)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: Animations

    static let springResponse: Animation = .spring(response: 0.4, dampingFraction: 0.8)
}

// MARK: - ContentView

struct ContentView: View {

    @EnvironmentObject var audioManager: MFiAudioManager
    @EnvironmentObject var streamManager: LiveKitStreamManager
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Full-bleed gradient background
            Theme.backgroundGradient
                .ignoresSafeArea()

            // Main vertical layout
            VStack(spacing: 0) {
                StatusBar(showSettings: $showSettings)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ModeSelector()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                CaptionScrollView()
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                TranslationToggle()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .environmentObject(audioManager)
        .environmentObject(streamManager)
    }
}
