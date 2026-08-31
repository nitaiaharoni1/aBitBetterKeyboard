import Foundation

extension SharedStore {

    // MARK: Cloud model

    /// The user's explicit, revocable permission for cloud AI processing.
    /// Computed from the App Group at use time because the containing app and
    /// keyboard extension are separate processes.
    public var allowsCloudAIProcessing: Bool {
        get { BackendTransport.allowsCloudAIProcessing(defaults: defaults) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.cloudAIProcessingAllowed)
        }
    }

    /// The backend every cloud call goes to, exactly as typed.
    ///
    /// **One key, and it is the one the whole product turns on.** Three readers
    /// live off it — `KeyboardController`'s text actions, `ScreenReadService` in the
    /// capture process, and `ScreenContextSession` — and all three reach it through
    /// `BackendTransport.configured`. This is the writer, and until `CloudModelView`
    /// there was effectively only one, hidden on the Screen Context screen under a
    /// heading about screen reading, so a Hebrew rewrite failed forever with no way
    /// to find out why.
    ///
    /// Computed through `userDefaults` rather than `@Published`, exactly like
    /// `customTone`: the value is read by another process at the moment of a tap,
    /// and a published copy filled at launch would be the stale one. Empty removes
    /// the key rather than storing "", because `URL(string: "")` is a URL and a
    /// stored empty string would read back as a configured backend with no scheme.
    /// **Falls back to `BackendTransport.bundledDefaultURL` exactly as
    /// `BackendTransport.configured` does, and that agreement is the point.** This
    /// getter is what `CloudModelView` fills its field from, so a getter answering
    /// "" while the transport quietly used the built-in address would put an empty
    /// box and the words "Nothing set" in front of a user whose Hebrew rewrites
    /// were working. The screen has to describe the send that will actually happen.
    public var cloudBackendURL: String {
        get { BackendTransport.effectiveURL(defaults: defaults) }
        set { write(newValue, forKey: Key.cloudBackendURL) }
    }

    /// The optional bearer token sent beside it. See `BackendTransport.send` for
    /// what it is and is not, and `CloudModelView` for where it is stored.
    public var cloudBackendToken: String {
        get { defaults.string(forKey: Key.cloudBackendToken) ?? "" }
        set { write(newValue, forKey: Key.cloudBackendToken) }
    }

    /// The bearer `AppAttestation` writes once the hardware has proved this app.
    /// Never typed, never shown, and the only one a shipping install has. See
    /// `BackendTransport.storedToken` for why it is a second key rather than
    /// reusing `cloudBackendToken`.
    public var cloudSessionToken: String {
        get { defaults.string(forKey: Key.cloudSessionToken) ?? "" }
        set { write(newValue, forKey: Key.cloudSessionToken) }
    }

    /// The App Attest key the current attempt is attesting with, kept across
    /// attempts and across launches.
    ///
    /// **Stored because Apple's retry instruction is "the same key and the same
    /// `clientDataHash`".** `serverUnavailable` is documented as transient and
    /// documented as retryable *only* that way — asking again with a fresh key
    /// and a fresh challenge is a different request, and Apple says repeating
    /// the identical one is what preserves the device's risk metric. A key that
    /// lived in a local made every retry a new device as far as Apple's service
    /// was concerned.
    ///
    /// Cleared on success, because a key can be attested exactly once: keeping it
    /// would make the ninety-day refresh fail with `invalidKey` on its first try
    /// every single time. Also cleared *on* `invalidKey`, which is the answer for
    /// a key from an install Apple no longer recognises.
    public var attestKeyId: String {
        get { defaults.string(forKey: Key.attestKeyId) ?? "" }
        set { write(newValue, forKey: Key.attestKeyId) }
    }

    /// What the last attestation attempt did, in one sentence a person can read.
    ///
    /// **The whole point is that this used to be nothing at all.** Attestation is
    /// the only thing standing between a fresh install and a working keyboard, it
    /// runs unattended at launch, and every failure went into a `try?`. So an
    /// install where it failed showed "Open AI Keyboard once to reconnect" on
    /// every AI action, the user opened the app, the app said "Open AI Keyboard
    /// once to connect it", and there was no third screen — no log, no code, no
    /// reason — anywhere on the device or on the server. That is the state this
    /// property exists to end.
    public var attestationReport: String {
        get { defaults.string(forKey: Key.attestationReport) ?? "" }
        set { write(newValue, forKey: Key.attestationReport) }
    }

    /// When that attempt happened. Also the automatic path's cooldown: a launch
    /// and a foreground both ask, and attestation is rate-limited by Apple, so
    /// two attempts a few seconds apart spend a real allowance to learn the same
    /// thing twice.
    public var attestationCheckedAt: Date? {
        get {
            let stamp = defaults.double(forKey: Key.attestationCheckedAt)
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set {
            objectWillChange.send()
            guard let newValue else {
                defaults.removeObject(forKey: Key.attestationCheckedAt)
                return
            }
            defaults.set(newValue.timeIntervalSince1970, forKey: Key.attestationCheckedAt)
        }
    }

    /// Whether an AI action would find a cloud engine right now. The same question
    /// `BackendTransport.configured` answers, asked of this store so a screen can
    /// render it.
    public var hasCloudModel: Bool { BackendTransport.isReady(defaults: defaults) }

    func write(_ value: String, forKey key: String) {
        objectWillChange.send()
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }
}
