// MARK: - CaptionEntry.swift
// StarLink — Gemini Live Hearing Aid Translation
//
// Value type representing a single line of translated caption
// streamed back from the Gemini translation agent via LiveKit
// data channel.
// ──────────────────────────────────────────────────────────────────

import Foundation

/// An immutable snapshot of one caption line.
///
/// `isPartial` marks entries that the agent is still streaming.
/// The ``LiveKitStreamManager`` replaces the last partial entry
/// in-place until a final (non-partial) entry arrives, giving
/// users a smooth "typing" effect in the caption list.
struct CaptionEntry: Identifiable, Equatable, Sendable {

    /// Stable identity for SwiftUI diffing.
    let id: String

    /// Wall-clock time when this caption was received.
    let timestamp: Date

    /// The original script (ambient audio captured).
    let originalText: String

    /// The translated script (Korean speech).
    let translatedText: String

    /// The detected language of the input speech (e.g. "en", "ja", "zh", "ko", or "unknown").
    let language: String?

    /// For backward compatibility, exposes the translated text content.
    var text: String {
        translatedText
    }

    /// `true` while the agent is still streaming this segment.
    /// Once the final text arrives, a new entry with
    /// `isPartial == false` replaces it.
    let isPartial: Bool

    // MARK: – Convenience Initialiser

    /// Creates a new entry with an auto-generated `id` and the
    /// current date as `timestamp`.
    init(
        originalText: String,
        translatedText: String,
        isPartial: Bool = false,
        language: String? = nil,
        id: String = UUID().uuidString,
        timestamp: Date = .now
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.isPartial = isPartial
        self.language = language
        self.timestamp = timestamp
    }
}
