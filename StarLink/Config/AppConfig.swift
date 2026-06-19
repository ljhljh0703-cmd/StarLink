// MARK: - AppConfig.swift
// StarLink — Gemini Live Hearing Aid Translation
//
// Centralised compile-time configuration for LiveKit connectivity,
// audio pipeline parameters, and UI constraints.
// ──────────────────────────────────────────────────────────────────

import Foundation

/// Single source of truth for every tuneable constant in the app.
///
/// All values are `static let` so the compiler can inline them and
/// the linter catches any accidental mutation attempts.
enum AppConfig {

    // MARK: – LiveKit Connection

    /// Helper to load values from Secrets.plist.
    private static func loadSecret(named key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist[key] as? String
    }

    /// WebSocket URL of the LiveKit Cloud (or self-hosted) server.
    static var livekitURL: String {
        if let customURL = UserDefaults.standard.string(forKey: "custom_livekit_url"), !customURL.isEmpty {
            return customURL
        }
        if let url = loadSecret(named: "LIVEKIT_URL"), !url.isEmpty {
            return url
        }
        // No hardcoded fallback (open-source). Configure via Secrets.plist
        // (LIVEKIT_URL) or the in-app Settings screen.
        return ""
    }
    
    /// Developer / CI token. In production swap this out for a
    /// short-lived JWT obtained from your token server.
    static var livekitToken: String {
        if let customToken = UserDefaults.standard.string(forKey: "custom_livekit_token"), !customToken.isEmpty {
            return customToken
        }
        if let token = loadSecret(named: "LIVEKIT_TOKEN"), !token.isEmpty {
            return token
        }
        // No hardcoded fallback (open-source). Provide a short-lived JWT via
        // Secrets.plist (LIVEKIT_TOKEN), the in-app Settings screen, or a
        // token server (see tokenServerURL / backend/server.py).
        return ""
    }

    /// Optional production token server URL. If set, the app will fetch tokens dynamically
    /// from this URL instead of using the static livekitToken.
    static var tokenServerURL: String? {
        if let customServer = UserDefaults.standard.string(forKey: "custom_token_server_url"), !customServer.isEmpty {
            return customServer
        }
        return loadSecret(named: "TOKEN_SERVER_URL")
    }

    /// Default room name that the Python translation agent also joins.
    static let roomName = "starlink-translation"

    // MARK: – Audio Pipeline

    /// Target sample rate for the upstream mic capture sent to Gemini.
    /// 16 kHz mono is the sweet-spot for speech recognition quality
    /// vs. bandwidth.
    static let sampleRate: Double = 16_000

    /// Mono channel — hearing-aid streaming is always mono.
    static let channels: UInt32 = 1

    // MARK: – UI / Captioning

    /// Maximum number of caption entries retained in memory.
    /// Older entries are pruned on a FIFO basis.
    static let maxCaptionHistory = 100
}
