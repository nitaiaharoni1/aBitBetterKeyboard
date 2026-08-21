import Foundation
import os

/// What the hosts this keyboard has served actually said about their own text
/// fields.
///
/// **The guard this counts rests on an unanswered question, and until now the
/// answer was written where nobody could read it.** `SecureField.permitsRead`
/// refuses Reply on a secure field and **permits on silence**, because `nil` is
/// an unimplemented optional protocol member rather than a password field. That
/// is only safe if silence really is common and a positive `true` really does
/// arrive when it matters — and nothing anywhere has ever been able to say which
/// hosts answer at all. The old count went into `CaptureIntent.refusedSecure`
/// through the capture channel, and **nothing in this repository read those
/// fields back**: not the app, not the broadcast extension, not Settings, not
/// `Bar/screen-context`. On top of that the channel is only created by
/// `startConsuming`, which is gated on `FeatureFlags.screenCaptureReply`, so in a
/// v1 build the counters could not move at all. NIT-187 is that issue and this is
/// its answer.
///
/// It is the fourth boot-scoped App Group record and deliberately the same shape
/// as `KeyboardPresence`, `KeyboardMemoryPeak` and `KeyboardLaunchRecord`: a pure
/// `merge`, `load(from:)` / `record(_:at:)` overloads so a test can take an
/// explicit URL, `bootIdentity` from `kern.boottime`, and a Settings →
/// Diagnostics row. Being independent of the capture channel is the point —
/// `permitsRead` is reached on **every Reply tap**, and Reply ships in v1 sourced
/// from the pasteboard, so this fills up whether the screen-capture flag is on or
/// off.
///
/// **`permitted` is not stored, because it is arithmetic.** The two refusal
/// reasons are mutually exclusive by construction — `permitsRead` returns on
/// `secure == true` before it ever looks at the content type — so
/// `decisions - refusedSecure - refusedContentType` is exactly the number of taps
/// that were allowed through. A stored fourth counter would be a second spelling
/// of the same fact and something for the other three to eventually disagree
/// with.
public struct SecureDecisionRecord: Codable, Equatable, Sendable {

    /// Every decision `permitsRead` made this boot. The denominator: a count of
    /// refusals means one thing over three taps and another over three hundred.
    public let decisions: Int

    /// How many of those had a host that had actually implemented
    /// `isSecureTextEntry`. **This is the number the record exists for.** Zero
    /// against a large `decisions` is the open question answered: no host tells
    /// this keyboard anything, so "silence permits" is the whole of the rule and
    /// the `true` branch is unreachable in practice.
    public let answered: Int

    /// How many were refused because a host said the field *is* secure. Apple
    /// documents that the system swaps in its own keyboard for a secure field, so
    /// this branch "essentially cannot fire" — a non-zero reading here would be
    /// the first evidence against that sentence and is worth seeing on its own.
    public let refusedSecure: Int

    /// How many were refused by `SecureField.sensitive` instead: a field that did
    /// not call itself secure but declared a password, one-time code or card
    /// number content type. Counted apart from the above because it is the one
    /// refusal that catches something iOS does not already handle.
    public let refusedContentType: Int

    public let recordedAt: UInt64
    public let bootIdentity: UInt64

    public init(
        decisions: Int, answered: Int, refusedSecure: Int, refusedContentType: Int,
        recordedAt: UInt64, bootIdentity: UInt64
    ) {
        self.decisions = decisions
        self.answered = answered
        self.refusedSecure = refusedSecure
        self.refusedContentType = refusedContentType
        self.recordedAt = recordedAt
        self.bootIdentity = bootIdentity
    }

    /// One decision, already taken.
    ///
    /// **The truth table stays in `SecureField` and this carries its answer**,
    /// which is forced as well as tidy: this target is Foundation-only and
    /// `UITextContentType` is UIKit, so the type that decides cannot live here.
    /// The caller is `ScreenContextSession.permitsRead`, and it is the only one.
    public struct Decision: Sendable, Equatable {
        /// `secure != nil`: the host implemented the optional trait at all.
        public let answered: Bool
        /// `secure == true`.
        public let refusedSecure: Bool
        /// Refused by the content type, which by construction can only be true
        /// when `refusedSecure` is false.
        public let refusedContentType: Bool

        public init(answered: Bool, refusedSecure: Bool, refusedContentType: Bool) {
            self.answered = answered
            self.refusedSecure = refusedSecure
            self.refusedContentType = refusedContentType
        }
    }

    /// Folds one decision into the record, or starts a new one for this boot.
    ///
    /// Pure, and non-optional for the reason `KeyboardLaunchRecord.merge` is:
    /// every call is a decision that has just been taken, so there is no "nothing
    /// moved" case for an optional to describe.
    ///
    /// **A record from a previous boot is replaced outright**, however high its
    /// counts. The question is about the hosts this phone has been used with
    /// since it restarted; carrying last week's totals forward would answer a
    /// question nobody can reproduce.
    public static func merge(
        _ decision: Decision, into existing: SecureDecisionRecord?,
        now: UInt64 = CaptureClock.now(), bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> SecureDecisionRecord {
        let base: SecureDecisionRecord
        if let existing, existing.bootIdentity == bootIdentity {
            base = existing
        } else {
            base = SecureDecisionRecord(
                decisions: 0, answered: 0, refusedSecure: 0, refusedContentType: 0,
                recordedAt: now, bootIdentity: bootIdentity)
        }
        return SecureDecisionRecord(
            decisions: base.decisions + 1,
            answered: base.answered + (decision.answered ? 1 : 0),
            refusedSecure: base.refusedSecure + (decision.refusedSecure ? 1 : 0),
            refusedContentType: base.refusedContentType + (decision.refusedContentType ? 1 : 0),
            recordedAt: now, bootIdentity: bootIdentity)
    }

    /// Taps that were allowed through. Arithmetic rather than a stored field —
    /// see the type's own doc comment.
    public var permitted: Int { decisions - refusedSecure - refusedContentType }

    // MARK: Where it lives

    static let fileName = "secure-decisions.json"

    /// Nil in the keyboard until the user grants Full Access, the same signal
    /// `KeyboardPresence.url`, `KeyboardMemoryPeak.url` and
    /// `KeyboardLaunchRecord.url` all rest on.
    public static var url: URL? {
        SharedContainer.url?.appendingPathComponent(fileName)
    }

    // MARK: Reading

    /// The record the keyboard left, or nil.
    ///
    /// Nil is "nobody has tapped Reply with Full Access since this shipped" and
    /// is **not** a reading of zero decisions. Settings must not render it as
    /// one: a zero would look like an answer, and the whole hazard NIT-187
    /// records is a zero that means the question was never asked.
    public static func load() -> SecureDecisionRecord? {
        guard let url else { return nil }
        return load(from: url)
    }

    /// Reads from a path of the caller's choosing. Public for the reason
    /// `KeyboardLaunchRecord.load(from:)` is: `AIKeyboardCoreTests` carries no App
    /// Group entitlement, yet the simulator hands it a real container anyway, so
    /// a test against the singleton would prove nothing about a device *and*
    /// would write into state the app and keyboard actually share.
    public static func load(from url: URL) -> SecureDecisionRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SecureDecisionRecord.self, from: data)
    }

    // MARK: Writing

    /// The queue every decision is written on, and **serial for the reason
    /// `KeyboardViewController.launchQueue` is serial.**
    ///
    /// `record` is read-modify-write on one file and every field here is a
    /// counter, so two of these on a concurrent queue can interleave and lose an
    /// increment. A lost increment on a counter is not one missing reading, it is
    /// a total that is quietly wrong — and `answered` reading low is exactly the
    /// direction that would make the open question look settled when it is not.
    ///
    /// The queue lives on the type rather than at the call site because, unlike
    /// the three records `KeyboardViewController` writes, this one is noted from
    /// inside the package and there is nowhere else that owns the decision.
    private static let queue = DispatchQueue(
        label: "com.nitai.aikeyboard.secure-decisions", qos: .utility)

    /// Counts one decision, off the caller's thread.
    ///
    /// This is what `permitsRead` calls. The write is dispatched because
    /// `permitsRead` runs on the main actor inside a Reply tap, and a file write
    /// between the tap and the panel is latency the user pays to answer a
    /// question that is not theirs.
    public static func note(_ decision: Decision) {
        let now = CaptureClock.now()
        queue.async { record(decision, now: now) }
    }

    /// Returns once every write queued before it has landed.
    ///
    /// **Its only caller is a test tear-down, and it exists because this is the
    /// one record written from inside the package rather than from
    /// `KeyboardViewController`.** `ScreenContextReadTests` drives `permitsRead`
    /// directly, so it writes into the real App Group container the simulator
    /// hands `AIKeyboardCoreTests` — and a tear-down that deleted the file
    /// without this would race the dispatched write and leave it behind about as
    /// often as not. The three older records need nothing like it because no test
    /// reaches their singleton path at all.
    ///
    /// `sync` on a serial queue is the whole mechanism: the block cannot start
    /// until everything queued ahead of it has finished.
    public static func waitForPendingWrites() {
        queue.sync {}
    }

    /// Folds one decision into the stored record, and logs it either way.
    @discardableResult
    public static func record(
        _ decision: Decision, now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> SecureDecisionRecord? {
        log.notice(
            """
            secure decision answered=\(decision.answered, privacy: .public) \
            refusedSecure=\(decision.refusedSecure, privacy: .public) \
            refusedContentType=\(decision.refusedContentType, privacy: .public)
            """)
        guard let url else { return nil }
        return record(decision, at: url, now: now, bootIdentity: bootIdentity)
    }

    /// Writes to a path of the caller's choosing. See `load(from:)` for why this
    /// is public.
    @discardableResult
    public static func record(
        _ decision: Decision, at url: URL, now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> SecureDecisionRecord? {
        let existing = load(from: url)
        let merged = merge(decision, into: existing, now: now, bootIdentity: bootIdentity)

        guard let data = try? JSONEncoder().encode(merged),
            (try? data.write(
                to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]))
                != nil
        else {
            log.error("secure decision write failed at \(url.lastPathComponent, privacy: .public)")
            return existing
        }
        return merged
    }

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "SecureDecision")
}
