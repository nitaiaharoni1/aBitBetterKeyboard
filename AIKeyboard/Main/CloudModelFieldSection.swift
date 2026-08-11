import AIKeyboardCore
import SwiftUI

/// The "Where AI Keyboard sends its work" card: server URL field, token field,
/// status line and Save button.
///
/// **Validated exactly as `BackendTransport.configured` validates** — parses as
/// a `URL`, scheme begins `http` — so a value this section accepts is one the
/// transport will accept. A field that took a string the transport then
/// rejected would leave the user looking at a filled-in box and a keyboard that
/// still says no cloud model is set up. The rule being mirrored is pinned on
/// the other side by
/// `BackendTransportSuiteTests.testConfiguredReadsWhicheverStoreItIsGiven`,
/// including the two key names; a change there is what would make this section
/// wrong, and it is the test that would say so.
struct CloudModelFieldSection: View {
    @EnvironmentObject private var store: SharedStore

    /// Mirrored out of the shared store so the fields are editable, and written
    /// back only when the URL parses. See `save()`.
    @State private var url = ""
    // The token field is a developer door, not a user setting — see the type's
    // doc comment. `token` only backs a control that exists in Debug, so it only
    // exists there too; a Release build with nowhere to type one has nothing to
    // mirror.
    #if DEBUG
    @State private var token = ""
    #endif
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Where AI Keyboard sends its work")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    // Says the true state of a fresh install. Until 2026-08-10 that
                    // state was "there is nowhere to send to", and this line said
                    // so; there is a deployed server now
                    // (`BackendTransport.bundledDefaultURL`), the address below is
                    // filled in from it, and — since App Attest started filling the
                    // bearer — a shipping install has nothing left to paste in.
                    #if DEBUG
                    Text(
                        "AI Keyboard comes pointing at our server, already filled in below. It needs the access token before it will answer: paste yours in, or replace both with your own server."
                    )
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    #else
                    Text(
                        "AI Keyboard comes pointing at our server, already filled in below, and connects to it on its own. Replace the address to point it at a server of your own instead."
                    )
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    #endif

                    TextField("https://example.com", text: $url)
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit { save() }
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(Theme.Surface.background)
                        )
                        .accessibilityIdentifier("cloud-model-url")
                        .accessibilityLabel("Cloud model server address")

                    // **A `SecureField`, and that is a shoulder-surfing fix, not a
                    // storage fix.** The token is written to the App Group plist
                    // beside the URL, in plaintext, and that container is included
                    // in device backups. The right home is the Keychain with a
                    // shared access group, which all three targets can reach — and
                    // it is deliberately not done here, because the reader is
                    // `BackendTransport.configured` in `AIKeyboardShared`, and a
                    // token written to the Keychain by this screen and still read
                    // out of `UserDefaults` by the keyboard and the capture process
                    // is worse than either half alone. It has to move on both sides
                    // in one change. Until then the field says what it is storing,
                    // in the line under it, rather than implying more safety than
                    // it has by hiding the characters.
                    //
                    // Debug only, along with everything below that describes it: a
                    // shipping install has `AppAttestation` filling this bearer, and
                    // a field with nothing to type into it is not a setting, it is a
                    // question nobody can answer. It stays for Debug builds because
                    // the simulator has no Secure Enclave and cannot attest at all.
                    #if DEBUG
                    SecureField(tokenPrompt, text: $token)
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { save() }
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(Theme.Surface.background)
                        )
                        .accessibilityIdentifier("cloud-model-token")
                        .accessibilityLabel("Cloud model \(tokenPrompt)")
                    #endif

                    Text(status)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(isUsable ? Theme.Semantic.success : Theme.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    #if DEBUG
                    // Said rather than implied. The token is stored in the app's
                    // shared settings file, which is backed up with the phone; it
                    // is not in the Keychain yet. Somebody choosing what to paste
                    // in here is entitled to know that before they paste it.
                    Text(
                        "The token is kept in AI Keyboard's shared settings, which are included in your device backup. Use one you can revoke."
                    )
                    .font(Theme.Fonts.micro)
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    #endif

                    // **What the last connection attempt actually did, which
                    // this screen never said.** `AppAttestation` fills the
                    // bearer, it runs unattended at launch, and every failure
                    // used to go into a `try?` — so an install where it failed
                    // read "Open AI Keyboard once to connect it" here *and* on
                    // every AI action in the keyboard, which is advice to do the
                    // thing that had just silently not worked. There was no
                    // third screen to go to and no reason recorded anywhere on
                    // the device. This is that reason.
                    if !store.attestationReport.isEmpty {
                        Text(reportLine)
                            .font(Theme.Fonts.micro)
                            .foregroundStyle(Theme.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cloud-model-report")
                    }

                    PrimaryButton(title: "Save", icon: "checkmark") { save() }
                        .disabled(!isUsable && !typedURL.isEmpty)
                        .accessibilityIdentifier("cloud-model-save")

                    // Offered whatever the state, because "connected" can go
                    // stale — a token has ninety days and the service can be
                    // redeployed under a new signing secret, and both look like
                    // a working setup right up until the next AI action 401s.
                    SecondaryButton(title: isConnecting ? "Connecting…" : "Try again") {
                        reconnect()
                    }
                    .disabled(isConnecting)
                    .accessibilityIdentifier("cloud-model-reconnect")
                }
            }
        }
        .onAppear {
            url = store.cloudBackendURL
            #if DEBUG
            token = store.cloudBackendToken
            #endif
        }
    }

    // MARK: Connecting

    private func reconnect() {
        isConnecting = true
        Task {
            await AppAttestation.attestNow(store: store)
            isConnecting = false
        }
    }

    /// The report with its age, because a stale sentence read as a live one is
    /// the failure this whole line exists to end: "Apple's attestation service
    /// didn't answer" from four days ago describes nothing about right now.
    private var reportLine: String {
        guard let checked = store.attestationCheckedAt else { return store.attestationReport }
        return "\(store.attestationReport) \(Self.age.localizedString(for: checked, relativeTo: Date()))"
    }

    private static let age = RelativeDateTimeFormatter()

    // MARK: Validation and persistence

    /// The same two questions `BackendTransport.configured` asks, in the same
    /// order, so the two cannot disagree about one string.
    private var parsedURL: URL? {
        let raw = typedURL
        guard !raw.isEmpty, let parsed = URL(string: raw), parsed.scheme?.hasPrefix("http") == true
        else { return nil }
        return parsed
    }

    private var isUsable: Bool { parsedURL != nil }

    /// **"(optional)" was true of every backend until one shipped, and false of the
    /// one almost everybody will use.** The server this build points at gates on a
    /// bearer, so leaving this empty is not a choice, it is an unfinished setup that
    /// 401s every AI action. A backend somebody runs themselves may well have no
    /// gate, and for that one the word is still right — so this follows the address
    /// in the field above rather than picking one answer and being wrong half the
    /// time. Reads the typed value, not the stored one, so it changes as soon as
    /// somebody pastes their own server in.
    #if DEBUG
    private var tokenPrompt: String {
        let typed = typedURL
        let isBundled = typed.isEmpty || typed == BackendTransport.bundledDefaultURL
        return isBundled ? "Access token (required)" : "Access token (optional)"
    }
    #endif

    private var status: String {
        // An emptied box is not "off" — `BackendTransport.configured` falls back to
        // the built-in address, and saying "nothing set" here would describe a
        // keyboard that is in fact still sending. Saving an empty field is how you
        // get the built-in server back after typing over it.
        if typedURL.isEmpty {
            return "Empty. Tap Save to go back to the server AI Keyboard ships with."
        }
        guard isUsable else {
            return "That is not a web address. It has to begin with http:// or https://."
        }
        guard store.cloudBackendURL == typedURL else { return "Not saved yet. Tap Save." }
        // **"Saved and in use" was a lie for the one state a fresh install is
        // actually in.** The address ships filled in, so it saves and matches
        // immediately, and this line would have said the cloud was working while
        // every AI action came back 401 for want of a token. `hasCloudModel` is
        // `BackendTransport.isReady`, which is the same question the keyboard asks.
        #if DEBUG
        return store.hasCloudModel
            ? "Saved and in use."
            : "Saved, but there is no access token: AI actions will be refused until you paste one in."
        #else
        // Nothing here for a shipping install to paste in: `AppAttestation`
        // fills the bearer at launch, so the only honest report is whether
        // that attempt has succeeded, not whether a field is filled in.
        //
        // **"Open AI Keyboard once to connect it" was being read by somebody
        // standing in AI Keyboard.** It is the right sentence in the keyboard,
        // where the app is somewhere else; here it is an instruction to do the
        // thing you are already doing. The line under it says why, and the
        // button under that is the action.
        return store.hasCloudModel
            ? "Saved and connected."
            : "Saved, but not connected. AI actions will be refused until it is."
        #endif
    }

    /// Only a value the transport would accept is ever written, and an emptied
    /// field removes the key rather than storing "" — which `URL(string:)` would
    /// happily turn into a URL with no scheme.
    ///
    /// **Clearing the address no longer clears the token, and that changed with
    /// the shipped default.** It used to wipe both, which was right when an empty
    /// address meant there was no backend at all: a token for a server you had
    /// just disowned was debris. Now an empty address means "use the one AI
    /// Keyboard ships with", and that server needs a token — so wiping it would
    /// turn a reset into a keyboard that 401s on every AI action, with a filled-in
    /// address on screen saying it is in use. Clearing the token is what the token
    /// field is for.
    private func save() {
        guard let parsed = parsedURL else {
            guard typedURL.isEmpty else { return }
            store.cloudBackendURL = ""
            #if DEBUG
            store.cloudBackendToken = typedToken
            #endif
            // Show the address that is now in force rather than the empty box the
            // user just saved. `store.cloudBackendURL` answers the shipped default
            // for an absent value, which is exactly what the transport will use.
            url = store.cloudBackendURL
            return
        }
        url = parsed.absoluteString
        store.cloudBackendURL = parsed.absoluteString
        #if DEBUG
        store.cloudBackendToken = typedToken
        #endif
    }

    private var typedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    #if DEBUG
    private var typedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    #endif
}
