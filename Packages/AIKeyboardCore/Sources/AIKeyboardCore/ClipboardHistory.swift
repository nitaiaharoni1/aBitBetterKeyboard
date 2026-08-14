import Foundation

/// A pasteboard string that is allowed to become a clip.
///
/// Empty, whitespace-only, and over-long strings never enter the ledger. The
/// pasteboard can hold a copied document; storing that would bury every real
/// clip under one unreadable card. Validation lives here so `reconcile` and
/// the store decoder cannot disagree about what a clip is.
public struct ClipText: Equatable, Codable, Sendable {
    public let value: String

    public init?(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= ClipPolicy.maxCharacters else { return nil }
        self.value = trimmed
    }

    enum CodingKeys: String, CodingKey { case value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .value)
        guard let parsed = ClipText(raw: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "clip text is empty or over \(ClipPolicy.maxCharacters) characters")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }
}

public struct Clip: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let text: ClipText
    public let capturedAt: Date

    public init(id: UUID, text: ClipText, capturedAt: Date) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
    }
}

public enum ClipPolicy {
    public static let maxClips = 50
    public static let maxCharacters = 4000
    public static let quickAccessCount = 5
}

/// Clips plus the last pasteboard generation this keyboard reconciled.
///
/// The cursor is persisted on purpose. Clear, then a killed extension, must
/// not resurrect the same board string. A new copy increments `changeCount`
/// and is captured; the same generation is a no-op even after teardown.
public struct CopyclipRecord: Equatable, Codable, Sendable {
    public var clips: [Clip]
    public var lastChangeCount: Int

    public static let empty = CopyclipRecord(clips: [], lastChangeCount: -1)

    public init(clips: [Clip], lastChangeCount: Int) {
        self.clips = clips
        self.lastChangeCount = lastChangeCount
    }
}

/// Pure ledger for copied text this keyboard has seen.
///
/// A third-party keyboard cannot watch the pasteboard while it is not running.
/// History is therefore "every distinct string this process has snapshotted,"
/// not a system-wide clipboard. `reconcile` is the only writer of that fact:
/// same `changeCount` is a no-op, so appear + panel-open + the change
/// notification can all call it without inventing duplicates.
public enum ClipboardHistory {

    /// Idempotent. Same `changeCount` leaves the ledger untouched.
    ///
    /// Nil or unparseable text still advances `lastChangeCount`, so a later
    /// snapshot of the same empty board does not retry. An existing string
    /// moves to the front and keeps its id: swipe-delete needs a stable
    /// identity, and re-copying is "this again," not a new row.
    public static func reconcile(
        clips: [Clip],
        changeCount: Int,
        lastChangeCount: Int,
        rawText: String?,
        now: Date
    ) -> (clips: [Clip], lastChangeCount: Int) {
        if changeCount == lastChangeCount {
            return (clips, lastChangeCount)
        }
        guard let rawText, let text = ClipText(raw: rawText) else {
            return (clips, changeCount)
        }
        if let index = clips.firstIndex(where: { $0.text == text }) {
            let existing = clips[index]
            let moved = Clip(id: existing.id, text: existing.text, capturedAt: now)
            var next = clips
            next.remove(at: index)
            next.insert(moved, at: 0)
            return (next, changeCount)
        }
        let clip = Clip(id: UUID(), text: text, capturedAt: now)
        return (Array(([clip] + clips).prefix(ClipPolicy.maxClips)), changeCount)
    }

    public static func remove(id: UUID, from clips: [Clip]) -> [Clip] {
        clips.filter { $0.id != id }
    }

    public static func cleared() -> [Clip] { [] }

    /// Newest first, same order as the ledger. An empty query is the full
    /// list, the way emoji search opens on recents.
    public static func matching(query: String, in clips: [Clip]) -> [Clip] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return clips }
        return clips.filter { $0.text.value.localizedStandardContains(needle) }
    }
}
