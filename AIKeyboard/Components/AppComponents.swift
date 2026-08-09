import AVFAudio
import SwiftUI
import AIKeyboardCore

// MARK: - Background

/// Two slow-drifting colour blobs behind the content. Enough atmosphere to make
/// the app feel like a product rather than a settings screen, cheap enough to
/// leave running.
struct AmbientBackground: View {
    var intensity: Double = 1

    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.Surface.background

            Circle()
                .fill(Theme.Brand.start.opacity(0.22 * intensity))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: drift ? -90 : -130, y: drift ? -220 : -180)

            Circle()
                .fill(Theme.Brand.end.opacity(0.26 * intensity))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: drift ? 130 : 90, y: drift ? -60 : -110)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.md
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Surface.separator, lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var action: (title: String, handler: () -> Void)?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.Text.tertiary)

            Spacer()

            if let action {
                Button(action.title, action: action.handler)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.horizontal, Theme.Space.xxs)
    }
}

// MARK: - Rows

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            if let icon {
                IconBadge(systemName: icon)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Text.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Space.sm)

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct NavigationRow<Destination: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var badge: String?
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: Theme.Space.sm) {
                if let icon {
                    IconBadge(systemName: icon)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Text.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                    }
                }

                Spacer(minLength: Theme.Space.xs)

                if let badge {
                    Text(badge)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Text.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("row-\(title)")
        .accessibilityLabel(title)
    }
}

struct IconBadge: View {
    let systemName: String
    var tint: Color?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint ?? Theme.Brand.solid)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((tint ?? Theme.Brand.solid).opacity(0.13))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var icon: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.Text.onBrand)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Brand.gradient)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .pressable()
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Text.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
        }
        .pressable()
    }
}

// MARK: - Status

/// The three measurements behind the setup card.
///
/// The reading of them is `SetupState` in `AIKeyboardShared`, where it can be
/// tested; this is the half that has to be here, because `AVAudioApplication` is
/// AVFoundation and that target is linked on its own by the broadcast extension.
///
/// The third is the cloud model, and it is a measurement rather than an
/// assumption for the same reason the first two are: the card used to print "cloud
/// rewrites work" off a green Full Access tick alone, which on a stock install is
/// the opposite of the truth.
extension SetupState {
    static func current() -> SetupState {
        SetupState(
            presence: KeyboardPresence.load(),
            microphone: .current,
            cloudConfigured: BackendTransport.configured() != nil)
    }
}

extension MicrophonePermission {
    /// `AVAudioApplication.recordPermission` is the iOS 17 spelling and the iOS 26
    /// SDK still carries it undeprecated; the `AVAudioSession` property of the same
    /// name has been deprecated since iOS 17. Reading it prompts nothing.
    static var current: MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    let check: SetupCheck
    var actionTitle = "Settings"
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.xs)

            if check != .confirmed, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(spokenValue)
    }

    private var symbol: String {
        switch check {
        case .confirmed: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        case .blocked: return "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch check {
        case .confirmed: return Theme.Semantic.success
        case .unknown: return Theme.Text.tertiary
        case .blocked: return Theme.Semantic.warning
        }
    }

    private var spokenValue: String {
        switch check {
        case .confirmed: return "Done"
        case .unknown: return "Not checked yet"
        case .blocked: return "Needs attention"
        }
    }
}

// MARK: - Live keyboard preview

/// The real keyboard, typing into an in-memory document. Used in onboarding and
/// in the playground so the product can be felt before it is installed.
struct KeyboardPreview: View {
    @StateObject private var target = MockTextTarget()
    @StateObject private var controller: KeyboardController

    private let showsDocument: Bool
    private let placeholder: String
    private let seedText: String
    private let hint: String?

    init(
        seedText: String = "",
        language: KeyboardLanguage = .english,
        showsDocument: Bool = true,
        placeholder: String = "Type something…",
        hint: String? = nil
    ) {
        let document = MockTextTarget(text: seedText)
        _target = StateObject(wrappedValue: document)
        _controller = StateObject(
            wrappedValue: {
                let controller = KeyboardController(target: document, language: language)
                // There is no other keyboard to switch to inside the app, so the globe
                // key cycles languages only.
                controller.showsGlobeKey = true
                return controller
            }())
        self.showsDocument = showsDocument
        self.placeholder = placeholder
        self.seedText = seedText
        self.hint = hint
    }

    var body: some View {
        VStack(spacing: 0) {
            if let hint, showsHint {
                hintLine(hint)
            }
            if showsDocument {
                document
            }
            KeyboardView(controller: controller)
        }
        // On the container, not on the hint: the hint is removed from the tree
        // when it stops applying, so a modifier attached to it is gone before it
        // could animate anything.
        .animation(Theme.Motion.quick, value: showsHint)
        .onChange(of: target.text) { _, _ in
            controller.refreshSuggestions()
        }
    }

    /// The hint names the next useful thing to do *with the sentence that is
    /// already there*, so it has to leave the moment the user does something with
    /// it — typing, deleting, or opening the AI menu and taking a rewrite. An
    /// instruction that outlives the state it describes is how "type a sentence"
    /// ended up printed above a sentence.
    private var showsHint: Bool { !seedText.isEmpty && target.text == seedText }

    private func hintLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            SparkleMark(size: 13)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.top, Theme.Space.sm)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private var document: some View {
        ScrollView {
            Text(target.text.isEmpty ? placeholder : target.text)
                .font(.system(size: 17))
                .foregroundStyle(target.text.isEmpty ? Theme.Text.tertiary : Theme.Text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Surface.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.Brand.solid.opacity(0.35), lineWidth: 1.5)
                )
                .padding(Theme.Space.sm)
        }
        .frame(maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
    }
}
