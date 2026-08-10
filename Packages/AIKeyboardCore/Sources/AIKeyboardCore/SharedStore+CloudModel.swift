import Foundation

extension SharedStore {

    // MARK: Cloud model

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
