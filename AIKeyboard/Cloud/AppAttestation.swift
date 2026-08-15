import AIKeyboardCore
import BackgroundTasks
import CryptoKit
import DeviceCheck
import Foundation
import UIKit
import os

/// Proves to the backend that this is a genuine, unmodified build of this app on
/// real Apple hardware, and stores the token that proof buys.
///
/// **This lives in the containing app and nowhere else.** The keyboard and the
/// broadcast extension are separate bundle IDs, so an attestation raised there
/// would name a different app; Apple rate-limits attestation, so a keyboard
/// cannot do it per tap; and a keyboard extension has no network at all until
/// Full Access is granted. They read the token this writes, through the App
/// Group, exactly as they read the one that used to be typed in.
///
/// **Nothing here fails quietly any more, and the version that did is what this
/// file is a fix for.** Measured against the deployed service on 2026-08-11:
/// every app launch posted `/v1/challenge` and got a 200, *no* launch ever
/// posted `/v1/attest`, and every keyboard action posted `/v1/text` and got a
/// 401. So the flow was dying inside `DCAppAttestService` between the two, and
/// three separate design choices made that unrecoverable and undiagnosable —
/// the error went into a `try?`, the attempt happened once per launch and was
/// never retried, and the key was a local so a second attempt was a different
/// device to Apple. The user saw "Open AI Keyboard once to reconnect" on every
/// AI action, opened the app, and the app said the same thing back. Every one
/// of those three is fixed below, and the outcome of each attempt is written to
/// `SharedStore.attestationReport` and to the unified log under
/// `com.nitai.aikeyboard:AppAttest`.
@MainActor
public enum AppAttestation {

    /// Renew once the token is a third of the way through its life.
    ///
    /// The backend issues ninety days. Refreshing at thirty means a user who
    /// opens the app even occasionally is never near the edge, and the sixty-day
    /// margin is for the user who does not: they keep working until they do.
    static let refreshAfter: TimeInterval = 30 * 24 * 60 * 60

    /// How many times one run asks Apple before giving up.
    ///
    /// Apple's transient failure is `serverUnavailable`, and its documented
    /// remedy is to ask again with the *same* key and the *same* `clientDataHash`
    /// — a fresh key and a fresh challenge is a different request, and repeating
    /// the identical one is what preserves the device's risk metric. Three, not
    /// more, because a challenge is only good for five minutes and each ask
    /// spends a real allowance against Apple's per-device limit.
    static let attempts = 3

    /// Do not spend a second automatic attempt inside this window.
    ///
    /// A launch and a foreground both ask, and at cold start they arrive within
    /// a second of each other. The manual button on the Cloud model screen goes
    /// through `attestNow` and is deliberately not held to this: somebody who
    /// taps Try again is asking for exactly one more attempt, now.
    static let automaticCooldown: TimeInterval = 60

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "AppAttest")

    /// One run at a time, shared rather than merely exclusive: `.task` at
    /// launch, `.onChange(of: scenePhase)`, the daily background refresh, and
    /// now a 401 recovering through `SessionReattestation` (`BackendTransport
    /// .send`) can all land inside the same window. A caller that arrives
    /// while a run is already in flight awaits *that* run's own result rather
    /// than skipping — the old `Bool` guard let a second caller return before
    /// the first had written a token, which is exactly the "401 while an
    /// attestation is already running" case NIT-87 asks this to be safe
    /// against.
    private static var inFlight: Task<Void, Never>?

    /// Called at launch and on every return to the foreground. Does nothing at
    /// all in the common case.
    public static func refreshIfNeeded(store: SharedStore) async {
        // Idempotent: this is the earliest, most-called entry point, so by the
        // time any cloud action can be attempted, `BackendTransport.send` has
        // somewhere to send a 401 recovery. Extensions never call this, so
        // `SessionReattestation.shared` in their own process stays unset.
        await SessionReattestation.shared.register(AppAttestationReattestor())

        guard needsRefresh(store: store) else { return }
        // **A typed token means there is nothing to attest for.** It wins in
        // `BackendTransport.storedToken`, and the only place it exists is a
        // Debug build on a simulator, which has no Secure Enclave and cannot
        // attest at all. Without this line a working developer setup reports
        // "This device can't use App Attest" on the Cloud model screen for ever,
        // which is a true sentence about a keyboard that is answering fine.
        guard store.cloudBackendToken.isEmpty else { return }
        if let last = store.attestationCheckedAt,
            Date().timeIntervalSince(last) < automaticCooldown
        {
            return
        }
        await attest(store: store)
    }

    /// The Cloud model screen's Try again, which asks once more whatever the last
    /// attempt reported. Debug only in practice: the row that reaches that screen
    /// is compiled out of Release, because a connection the user cannot see is not
    /// a connection they should have to repair.
    public static func attestNow(store: SharedStore) async {
        await SessionReattestation.shared.register(AppAttestationReattestor())
        await attest(store: store)
    }

    /// The identifier `Info.plist` permits and `AIKeyboardApp` registers.
    ///
    /// **Named here rather than typed in three places**, because a background task
    /// whose identifier is absent from `BGTaskSchedulerPermittedIdentifiers`
    /// throws on submit, and one that is permitted but never registered crashes
    /// the app on launch. Neither failure is visible from the screen this feature
    /// has, which is none.
    public static let refreshTaskIdentifier = "com.nitai.aikeyboard.attest"

    /// Ask iOS to wake the app and let it reconnect while nobody is looking.
    ///
    /// **This is what makes the cloud invisible instead of merely unexplained.** A
    /// session token lives ninety days and only the containing app can renew one,
    /// so without this the honest instruction to a user whose token has aged out
    /// is "open an app you have no reason to open" — and the keyboard has no way
    /// to make that happen, since `UIApplication` does not exist in an extension
    /// and the responder-chain `openURL` trick is disallowed. With it, the app
    /// gets woken, attests, and the keyboard is working again before anybody
    /// notices it stopped.
    ///
    /// A day, not an hour: the token has a sixty-day margin before it expires, so
    /// there is nothing to be gained by asking more often, and `earliestBeginDate`
    /// is a floor iOS is free to ignore for far longer on a phone that is rarely
    /// charged. Submitting a request for an identifier that already has one
    /// replaces it, so calling this on every background is a no-op rather than a
    /// queue.
    public static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulators refuse to schedule at all, and a device with Background
            // App Refresh switched off refuses too. Neither is worth a screen:
            // launch and foreground still attest, which is every path that
            // existed before this one.
            log.notice("background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func needsRefresh(store: SharedStore) -> Bool {
        let existing = store.cloudSessionToken
        guard !existing.isEmpty, let expiry = SessionToken.expiry(of: existing) else { return true }
        return expiry.timeIntervalSinceNow < (90 * 24 * 60 * 60) - refreshAfter
    }

    /// The coordinating wrapper: starts a run, or joins the one already
    /// happening. See `inFlight`'s own comment for why a caller that arrives
    /// mid-run must wait for that run's answer rather than return early.
    static func attest(store: SharedStore) async {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await runAttest(store: store) }
        inFlight = task
        defer { inFlight = nil }
        await task.value
    }

    private static func runAttest(store: SharedStore) async {
        guard DCAppAttestService.shared.isSupported else {
            finish(false, "This device can't use App Attest.", store: store)
            return
        }
        // **Guarded, not force-unwrapped, and the difference is a launch
        // crash.** `effectiveURL` returns the stored string as it was typed —
        // only `configured()` ever asks whether it parses — and this runs at
        // launch on a value written by a different process into a shared plist.
        // A stored string with a space in it makes `URL(string:)` nil, and a
        // `!` there takes the app down before it draws. Refused the same two
        // ways `BackendTransport.configured` refuses, so a URL this accepts is
        // one a call would actually go to.
        guard let base = URL(string: BackendTransport.effectiveURL()),
            base.scheme?.hasPrefix("http") == true
        else {
            finish(false, "The cloud model address isn't a web address.", store: store)
            return
        }

        // **The user leaves for the app they were typing in, and iOS suspends
        // this process a few seconds later.** Attestation is two round trips to
        // Apple and one to our own service; the whole point of it is that it
        // happens without being asked for, so the person who triggered it has no
        // reason to stay and watch. Without an assertion the run is frozen
        // mid-flight and there is no partial state to resume from, which is a
        // standing candidate for the launches that fetched a challenge and never
        // posted an attestation.
        let assertion = BackgroundAssertion(name: "AppAttest")
        defer { assertion.end() }

        let challenge: String
        do {
            challenge = try await fetchChallenge(base: base)
        } catch {
            finish(false, "Couldn't reach the server: \(error.localizedDescription)", store: store)
            return
        }
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))

        guard let (keyId, attestation) = await raise(clientDataHash, store: store) else { return }

        do {
            store.cloudSessionToken = try await exchange(
                attestation, keyId: keyId, challenge: challenge, base: base)
            finish(true, "Connected.", store: store)
        } catch {
            finish(false, error.localizedDescription, store: store)
        }
    }

    // MARK: Asking Apple

    /// Apple's half: a key, and an attestation of it against our challenge.
    ///
    /// Returns nil having already written the report, so the caller has nothing
    /// to add.
    private static func raise(
        _ clientDataHash: Data, store: SharedStore
    ) async -> (String, Data)? {
        let service = DCAppAttestService.shared
        var reason = "Apple didn't answer."

        for attempt in 1...attempts {
            do {
                // Reused across attempts and across launches, per Apple's retry
                // instruction. Absent only on the first attempt of a device that
                // has never got this far, and after an `invalidKey` below.
                var keyId = store.attestKeyId
                if keyId.isEmpty {
                    keyId = try await service.generateKey()
                    store.attestKeyId = keyId
                }
                let attestation = try await service.attestKey(
                    keyId, clientDataHash: clientDataHash)
                // **Spent the moment Apple answers, whatever happens next.** A
                // key is attestable exactly once, so it is already dead by the
                // time the exchange below runs — and if that exchange fails,
                // leaving this stored costs the next run a whole attempt to
                // rediscover it as `invalidKey`. It is also what stops the
                // ninety-day refresh opening with a guaranteed failure.
                store.attestKeyId = ""
                return (keyId, attestation)
            } catch let error as DCError {
                reason = describe(error)
                log.error("attempt \(attempt) failed: \(reason, privacy: .public)")
                switch error.code {
                case .invalidKey:
                    // The stored key is one Apple no longer recognises — from an
                    // install that is gone, or from the documented state a device
                    // can get stuck in. A fresh key is the only answer, and it is
                    // the one case where changing the request is right.
                    store.attestKeyId = ""
                case .serverUnavailable:
                    // Transient. Ask again, unchanged, which is the whole reason
                    // the key is in the store rather than in a local.
                    break
                default:
                    // `featureUnsupported` and `invalidInput` do not improve by
                    // being asked twice.
                    finish(false, reason, store: store)
                    return nil
                }
            } catch {
                reason = error.localizedDescription
                log.error("attempt \(attempt) failed: \(reason, privacy: .public)")
            }

            if attempt < attempts {
                try? await Task.sleep(for: .seconds(2 << (attempt - 1)))
            }
        }

        finish(false, reason, store: store)
        return nil
    }

    /// Plain words for the five things `DCError` can be, because this string is
    /// shown to whoever is looking at the Cloud model screen wondering why their
    /// keyboard says no.
    private static func describe(_ error: DCError) -> String {
        switch error.code {
        case .featureUnsupported:
            return "This device doesn't support App Attest."
        case .invalidInput:
            return "Apple rejected the attestation request as malformed."
        case .invalidKey:
            return "Apple didn't recognise this app's attestation key."
        case .serverUnavailable:
            return "Apple's attestation service didn't answer. Try again later."
        case .unknownSystemFailure:
            return "Attestation failed on the device (unknown system failure)."
        @unknown default:
            return "Attestation failed: \(error.localizedDescription)"
        }
    }

    // MARK: Talking to our own service

    private static func fetchChallenge(base: URL) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("v1/challenge"))
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let challenge = body["challenge"] as? String
        else { throw URLError(.cannotParseResponse) }
        return challenge
    }

    /// Trades a valid attestation for a ninety-day session token.
    ///
    /// **Throws with the status and the service's own words, where the version
    /// this replaces returned an indistinguishable nothing.** A 401 here is the
    /// service saying it looked at the attestation and refused it — a different
    /// problem, with a different fix, from a phone that is offline — and the two
    /// were the same silent `return`.
    private static func exchange(
        _ attestation: Data, keyId: String, challenge: String, base: URL
    ) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard status == 200 else {
            let detail = (body?["error"] as? String) ?? "no reason given"
            throw AttestationRefused("The server refused the attestation (\(status)): \(detail)")
        }
        guard let token = body?["token"] as? String else {
            throw AttestationRefused("The server accepted the attestation but sent no token.")
        }
        return token
    }

    // MARK: Reporting

    private static func finish(_ ok: Bool, _ note: String, store: SharedStore) {
        store.attestationReport = note
        store.attestationCheckedAt = Date()
        if ok {
            log.notice("attested: \(note, privacy: .public)")
        } else {
            log.error("not attested: \(note, privacy: .public)")
        }
    }
}

/// `AppAttestation`'s conformance to `SessionReattestor`, registered with
/// `SessionReattestation.shared` at the top of `refreshIfNeeded` and
/// `attestNow` — see those for why that is early enough.
///
/// **Holds nothing**, rather than capturing a `SharedStore`: `attest(store:)`
/// only ever runs against `.shared`, the same singleton `AIKeyboardApp`
/// passes it, and `cloudSessionToken` reads `UserDefaults` fresh on every
/// call — so there is nothing here that could go stale, and nothing that
/// would make this struct not trivially `Sendable`.
private struct AppAttestationReattestor: SessionReattestor {
    func reattest() async -> String? {
        await AppAttestation.attest(store: .shared)
        let token = SharedStore.shared.cloudSessionToken
        return token.isEmpty ? nil : token
    }
}

/// Keeps the process alive long enough to finish attesting, and cannot be ended
/// twice.
///
/// **An expiration handler is not optional here.** `beginBackgroundTask` without
/// one hands back an assertion nobody ends when the system's patience runs out,
/// and iOS terminates an app that lets that happen — trading a keyboard that
/// cannot reach the cloud for one that gets killed in the background. So the
/// handler ends it, the caller's `defer` ends it, both call the same method, and
/// the identifier is cleared on the way through: `endBackgroundTask` on an
/// already-ended assertion, or on `.invalid`, is a UIKit error in its own right.
@MainActor
private final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // UIKit promises this on the main thread, which is the actor this
            // object lives on; `assumeIsolated` states that rather than hopping
            // to a later main-thread turn we may not get.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Carries the service's own sentence up to the report. `LocalizedError` rather
/// than a bare `Error`, because `localizedDescription` on the latter prints
/// Foundation's "The operation couldn't be completed" boilerplate and drops the
/// only part worth reading.
private struct AttestationRefused: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
