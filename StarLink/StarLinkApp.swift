// StarLinkApp.swift
// StarLink — Premium Hearing Aid Translation
//
// Entry point for the StarLink iOS application.
// Initializes core managers and injects them into the SwiftUI environment.

import SwiftUI

@main
struct StarLinkApp: App {

    // MARK: - State Objects

    @StateObject private var audioManager: MFiAudioManager

    /// `LiveKitStreamManager` depends on `MFiAudioManager` for audio routing.
    /// We use a lazy initialization pattern via a separate factory to satisfy
    /// the @StateObject single-init requirement.
    @StateObject private var streamManager: LiveKitStreamManager

    // MARK: - Initializer

    init() {
        let audio = MFiAudioManager()
        _audioManager = StateObject(wrappedValue: audio)
        _streamManager = StateObject(wrappedValue: LiveKitStreamManager(audioManager: audio))
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(streamManager)
                .preferredColorScheme(.dark)
        }
    }
}
