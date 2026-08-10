import Foundation
import os

// MARK: - Publishing

extension ScreenReadService {

    func finish(
        _ ticket: Ticket,
        outcome: ScreenReadOutcome = .read,
        detail: String = "",
        reading: ScreenReading? = nil,
        provenance: AIProvenance = .cloud
    ) {
        // The sequence is taken at completion rather than from the ticket: a
        // request that arrived while this read ran was folded into it, and the
        // record has to carry the number the keyboard is waiting on.
        let sequence = state.withLock { state -> UInt64 in
            state.isReading = false
            // Cleared with the flag it belongs to: a stale identity left here
            // would let the *next* read fold a tap against the screen this one
            // was about.
            state.readingIdentity = .absent
            return max(state.answering, ticket.sequence)
        }

        publish(
            sequence: sequence, identity: ticket.identity, capturedAt: ticket.capturedAt,
            outcome: outcome, detail: detail, reading: reading, provenance: provenance)
    }

    func publish(
        sequence: UInt64,
        identity: FrameIdentity,
        capturedAt: UInt64,
        outcome: ScreenReadOutcome,
        detail: String,
        reading: ScreenReading? = nil,
        provenance: AIProvenance = .cloud
    ) {
        guard let session = state.withLock({ $0.sessionID }) ?? channel.status()?.sessionID else {
            Self.log.error("read finished with no session to publish it under")
            return
        }

        let record = ScreenReadingRecord(
            sessionID: session,
            requestSequence: sequence,
            frameIdentity: identity,
            capturedAt: capturedAt,
            readAt: CaptureClock.now(),
            provenance: Self.name(of: provenance),
            outcome: outcome,
            detail: detail,
            sender: reading?.sender ?? "",
            message: reading?.message ?? "",
            language: reading?.language.rawValue ?? "")

        do {
            try channel.publish(record)
            channel.count(\.readsCompleted)
            // The message itself is never logged. The unified log is readable by
            // anything with the device paired, and the whole point of this
            // pipeline is that a private conversation stays between the model and
            // the user.
            Self.log.notice(
                """
                read finished request=\(sequence, privacy: .public) \
                outcome=\(outcome.rawValue, privacy: .public) \
                sender=\(reading == nil ? "none" : "named", privacy: .public)
                """
            )
        } catch {
            Self.log.error("read could not be published: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func name(of provenance: AIProvenance) -> String {
        switch provenance {
        case .onDevice: return "onDevice"
        case .onDeviceBestEffort: return "onDeviceBestEffort"
        case .cloud: return "cloud"
        }
    }
}
