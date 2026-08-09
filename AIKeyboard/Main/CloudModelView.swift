import AIKeyboardCore
import SwiftUI

/// The one place the cloud model is configured, and the only writer of
/// `cloudBackendURL` in the app.
///
/// **Why this is a screen of its own, and why it is reached from Settings › AI
/// rather than living on Screen Context.** `BackendTransport.configured()` is
/// consulted by three readers — the keyboard's Fix, Rewrite, Tone and Reply, the
/// capture process's screen reader, and `ScreenContextSession` — and for most of
/// this project its only writer was a card headed "Where the screen is read", on a
/// screen entirely about screen recording. Nothing said that the same field was
/// what switched on Hebrew. So on a stock install the keyboard's primary language
/// failed at every AI action with "no cloud model is set up", Home asserted that
/// cloud rewrites worked, and Settings › AI held a tone picker and a switch that
/// controlled nothing.
///
/// A row on Screen Context pointing here would have been the smaller diff. It was
/// rejected because it leaves the setting *living* inside the feature that needs it
/// least often: text actions are what a keyboard does every minute, screen context
/// is a session somebody starts occasionally, and a user who has never opened
/// Screen Context has no reason to go looking there for the thing that makes their
/// keyboard work. Settings › AI is where somebody stands when AI does not work, so
/// the setting lives there and Screen Context carries the pointer instead — still
/// above its start button, because a broadcast started without this ends inside a
/// second.
///
/// The name is single by construction: `BackendTransport.settingsPath` is this
/// row's path, and every failure that dead-ends here prints it.
struct CloudModelView: View {
    @EnvironmentObject private var store: SharedStore

    /// Mirrored out of the shared store so the fields are editable, and written
    /// back only when the URL parses. See `save()`.
    @State private var url = ""
    @State private var token = ""

    var body: some View {
        ZStack {
            Theme.Surface.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    field
                    whatItIsFor
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Cloud model")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            url = store.cloudBackendURL
            token = store.cloudBackendToken
        }
    }

    // MARK: The field

    /// **Validated exactly as `BackendTransport.configured` validates** — parses as
    /// a `URL`, scheme begins `http` — so a value this screen accepts is one the
    /// transport will accept. A field that took a string the transport then
    /// rejected would leave the user looking at a filled-in box and a keyboard that
    /// still says no cloud model is set up. The rule being mirrored is pinned on
    /// the other side by
    /// `BackendTransportSuiteTests.testConfiguredReadsWhicheverStoreItIsGiven`,
    /// including the two key names; a change there is what would make this screen
    /// wrong, and it is the test that would say so.
    private var field: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Where AI Keyboard sends its work")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    // Says the true state of a fresh install rather than implying
                    // something is broken: there is no server to point at yet
                    // because nobody has deployed one, and that is a different
                    // sentence from "this failed".
                    Text(
                        "We do not run a server for you yet, so this is empty until you point it at your own. Nothing here is broken — there is just nowhere to send to."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    TextField("https://example.com", text: $url)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15).monospaced())
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
                    SecureField("Access token (optional)", text: $token)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15).monospaced())
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
                        .accessibilityLabel("Cloud model access token, optional")

                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(isUsable ? Theme.Semantic.success : Theme.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Said rather than implied. The token is stored in the app's
                    // shared settings file, which is backed up with the phone; it
                    // is not in the Keychain yet. Somebody choosing what to paste
                    // in here is entitled to know that before they paste it.
                    Text(
                        "The token is kept in AI Keyboard's shared settings, which are included in your device backup. Use one you can revoke."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                    PrimaryButton(title: "Save", icon: "checkmark") { save() }
                        .disabled(!isUsable && !typedURL.isEmpty)
                        .accessibilityIdentifier("cloud-model-save")
                }
            }
        }
    }

    // MARK: What depends on it

    /// Both jobs, named on the screen that does them, because the whole defect this
    /// screen exists to fix was one of them being invisible.
    private var whatItIsFor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What needs it")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    use(
                        icon: "textformat",
                        title: "Fix, Rewrite, Tone and Reply in Hebrew",
                        detail:
                            "Apple's on-device model does not list Hebrew, so those actions have nowhere to run without this. English, French, German and the rest of the languages Apple does list keep working on the device either way."
                    )
                    use(
                        icon: "eye",
                        title: "Reading the screen",
                        detail:
                            "Screen context sends one screenshot per Reply tap and gets back the sender, the message and its language. Without this a broadcast is refused the moment it starts, rather than recording your screen for nothing."
                    )
                }
            }
        }
    }

    private func use(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            IconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Reading and writing

    /// The same two questions `BackendTransport.configured` asks, in the same
    /// order, so the two cannot disagree about one string.
    private var parsedURL: URL? {
        let raw = typedURL
        guard !raw.isEmpty, let parsed = URL(string: raw), parsed.scheme?.hasPrefix("http") == true
        else { return nil }
        return parsed
    }

    private var isUsable: Bool { parsedURL != nil }

    private var status: String {
        if typedURL.isEmpty {
            return
                "Nothing set. Hebrew AI actions and screen context both stop here until there is. It takes a web address beginning http:// or https://."
        }
        guard isUsable else {
            return "That is not a web address. It has to begin with http:// or https://."
        }
        return store.cloudBackendURL == typedURL ? "Saved and in use." : "Not saved yet — tap Save."
    }

    /// Only a value the transport would accept is ever written, and an emptied
    /// field removes the key rather than storing "" — which `URL(string:)` would
    /// happily turn into a URL with no scheme.
    private func save() {
        guard let parsed = parsedURL else {
            guard typedURL.isEmpty else { return }
            store.cloudBackendURL = ""
            store.cloudBackendToken = ""
            token = ""
            return
        }
        url = parsed.absoluteString
        store.cloudBackendURL = parsed.absoluteString
        store.cloudBackendToken = typedToken
    }

    private var typedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var typedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Pointing at it

/// The row both Settings › AI and Screen Context show, so one setting is reached
/// by one name from both features that need it.
struct CloudModelRow: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        NavigationRow(
            title: "Cloud model",
            subtitle: store.hasCloudModel ? "Set up" : "Not set up",
            icon: "cloud"
        ) {
            CloudModelView()
        }
    }
}
