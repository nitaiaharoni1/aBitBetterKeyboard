import AIKeyboardCore
import Foundation

import os

/// The companion app's own instrumentation, and the boundary it may never cross.
///
/// **This type exists in the app target only, and that is load-bearing rather than
/// incidental.** `.claude/docs/analytics-policy.md` promises that
/// `AIKeyboardExtension` and `AIKeyboardBroadcast` emit zero events, forever,
/// independent of Full Access, subscription state, or any feature shipped later. A
/// promise like that survives exactly as long as the thing it forbids is hard to
/// do. So none of this lives in `AIKeyboardCore` or `AIKeyboardShared`, which both
/// extensions link: a keyboard-side call site would have to import a module the
/// extension does not have and cannot get, which turns "please don't" into a
/// compiler error.
///
/// **The install identifier is deliberately kept out of the App Group** for the
/// same reason. Every other piece of shared state in this project lives in
/// `SharedContainer.userDefaults` so the extension can read it; this one lives in
/// the app's own `UserDefaults.standard`, where the keyboard structurally cannot
/// reach it. If a future edit ever did put an event in the extension, it would have
/// no identifier to attach it to.
///
/// **Failure is silence.** Nothing here surfaces an error, retries, queues to disk,
/// or blocks a screen. An analytics call that can make a user wait is a bug with a
/// worse consequence than the missing number it was trying to record.
enum Analytics {

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "analytics")

    /// Whether this process is a test runner rather than somebody's phone.
    ///
    /// **A UI test walks the onboarding funnel end to end, and it would be
    /// counted as a person doing it.** `AIKeyboardUITests` drives the app by
    /// accessibility identifier and every one of its cases launches with at least
    /// one of `-uiTestReset`, `-uiTestSkipOnboarding`, `-uiTestCaptureChannel` or
    /// `-uiTestDictationChannel`. Left unsuppressed, one `xcodebuild test` run
    /// posts a completed ten-step onboarding, a Full Access grant and a keyboard
    /// confirmation from a machine, into the same funnel the product decisions are
    /// read out of. The events would be indistinguishable from real ones, because
    /// the whole point of the suite is to do exactly what a user does.
    ///
    /// Matched on the `-uiTest` prefix rather than on the four known arguments, so
    /// a fifth added later is silent by default. Getting this wrong in the
    /// permissive direction corrupts a number quietly; getting it wrong in the
    /// strict direction only loses events from a machine nobody was measuring.
    private static var isTestRun: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
    }

    static let optOutKey = "analytics.optedOut"

    /// Whether the user has switched counting off.
    ///
    /// **Not required by `.claude/docs/analytics-policy.md`, and worth having
    /// anyway.** The policy's defence is that the six events have no slot a piece
    /// of content could go in — `AnalyticsEvent` is a closed enum of `Int`, `Bool`
    /// and raw-value enums, so the never-list is enforced by the compiler rather
    /// than by a preference somebody has to find. That argument is sound and it
    /// is not the whole of what a person is entitled to: "you cannot send my
    /// words" and "you may not count me at all" are different asks, and only the
    /// first one was answered.
    ///
    /// Defaults to false (counting on), because the events are anonymous,
    /// resettable and carry nothing typed. An install that opts out keeps its
    /// identifier rather than clearing it: the switch is about what is sent from
    /// here on, and throwing the identifier away as a side effect would make
    /// "stop counting me" silently also mean "start a new identity", which is
    /// `reset()`'s job and the user's separate decision.
    ///
    /// Read at the top of both entry points rather than at the call sites, so a
    /// future event cannot be added that forgets to ask.
    static var isOptedOut: Bool {
        get { UserDefaults.standard.bool(forKey: optOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: optOutKey) }
    }

    /// The one entry point. Fire-and-forget: returns immediately, sends on a
    /// detached task, swallows every failure.
    static func record(_ event: AnalyticsEvent) {
        guard !isTestRun, !isOptedOut else { return }
        if let key = event.oncePerInstallKey {
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
        }
        let payload = envelope(for: event)
        Task.detached(priority: .background) { await send(payload) }
    }

    /// Fires `appSessionStarted` at most once per calendar day.
    ///
    /// The day boundary is the user's own calendar, not a 24-hour window from the
    /// last send: "did they come back today" is a question about days, and a
    /// rolling window would drift an hour later on every launch until a daily user
    /// read as an every-other-day one.
    static func recordSessionStartIfNewDay(now: Date = Date()) {
        // Guarded here as well as in `record`, because this one writes a latch
        // before it sends: a test run, or an opted-out install, would otherwise
        // stamp today's date and make a later launch skip its event.
        guard !isTestRun, !isOptedOut else { return }
        let today = Calendar.current.startOfDay(for: now)
        let key = "analytics.lastSessionDay"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
            Calendar.current.isDate(last, inSameDayAs: today)
        {
            return
        }
        UserDefaults.standard.set(today, forKey: key)
        record(.appSessionStarted(daysSinceInstall: daysSinceInstall(now: now)))
    }

    // MARK: The envelope

    /// Install identifier, app version, OS version, event name, client timestamp,
    /// and the event's own properties. Nothing else, ever.
    ///
    /// Not `identifierForVendor`: that survives a reinstall while any other app
    /// from the same vendor is installed, and it is the same value a second app
    /// could correlate against. The policy asks for an identifier that is locally
    /// generated and resettable, and `reset()` below is what makes it resettable.
    private static func envelope(for event: AnalyticsEvent) -> [String: AnalyticsValue] {
        var payload: [String: AnalyticsValue] = [
            "event": .string(event.name),
            "install_id": .string(installID),
            "app_version": .string(appVersion),
            "os_version": .string(osVersion),
            "sent_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        for (key, value) in event.properties { payload[key] = value }
        return payload
    }

    /// `ProcessInfo` rather than `UIDevice.current.systemVersion`, which reads the
    /// same number but is `@MainActor` in the current SDK. This envelope is built
    /// on whatever thread called `record`, and a main-actor hop to fetch a string
    /// that never changes would be a concurrency warning today and an error the
    /// day this target moves to the Swift 6 language mode.
    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private static let installIDKey = "analytics.installID"
    private static let installedAtKey = "analytics.installedAt"

    static var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIDKey)
        return fresh
    }

    /// Days since this install first ran, which is not days since the app was
    /// bought: a reinstall starts the count again, on purpose, because the
    /// identifier it is reported beside started again too.
    private static func daysSinceInstall(now: Date) -> Int {
        let installedAt: Date
        if let stored = UserDefaults.standard.object(forKey: installedAtKey) as? Date {
            installedAt = stored
        } else {
            installedAt = now
            UserDefaults.standard.set(now, forKey: installedAtKey)
        }
        let start = Calendar.current.startOfDay(for: installedAt)
        return Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: now))
            .day ?? 0
    }

    /// Forget the identifier and every once-per-install latch.
    ///
    /// The resettable half of "locally generated and resettable". Nothing calls it
    /// yet; it is what a Settings row would call, and it is here so that row is a
    /// view rather than a second implementation of this file's rules.
    static func reset() {
        let defaults = UserDefaults.standard
        for key in [installIDKey, installedAtKey, "analytics.lastSessionDay"] {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "analytics.sent.full_access_confirmed")
        defaults.removeObject(forKey: "analytics.sent.keyboard_added_confirmed")
    }

    // MARK: Transport

    /// One first-party endpoint on the backend this project already deploys, per
    /// the policy's section 5: no third-party SDK, because an analytics SDK is a
    /// closed binary running inside the process that holds Full Access to the
    /// shared container, and its "no content collected" claim cannot be checked
    /// against source the way this file can.
    ///
    /// Unauthenticated on purpose. App Attest gates the model calls because those
    /// cost money per request; a counter with no cost and no abuse profile does not
    /// earn a Secure Enclave round trip, and gating it would make the app's own
    /// setup funnel unmeasurable on exactly the installs where attestation is what
    /// failed.
    private static func send(_ payload: [String: AnalyticsValue]) async {
        let base = BackendTransport.effectiveURL()
        guard let url = URL(string: base.hasSuffix("/") ? base + "v1/event" : base + "/v1/event"),
            let body = try? JSONEncoder().encode(payload)
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // Deliberately terminal. A dropped event is a missing row in a funnel;
            // a retry queue is a second piece of state to get wrong, in the process
            // that holds the user's shared container.
            log.debug("analytics event dropped: \(error.localizedDescription, privacy: .public)")
        }
    }
}
