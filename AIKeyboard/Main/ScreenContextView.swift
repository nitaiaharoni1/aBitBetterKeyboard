import SwiftUI
import AIKeyboardCore

/// Where the capture session is started and stopped.
///
/// This screen carries the honesty burden for the whole feature. It has to say
/// what is read, what leaves the device, what is kept, and when it stops, in
/// language someone can check against what they observe.
struct ScreenContextView: View {
    @EnvironmentObject private var store: SharedStore
    @StateObject private var session = ScreenContextSession.shared

    var body: some View {
        ZStack {
            AmbientBackground(intensity: session.isLive ? 1 : 0.5)

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    hero
                    control
                    if session.isLive { liveDetail }
                    explanation
                    limits
                    if session.isLive { cloudToggle }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Screen Context")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle()
                    .fill(session.isLive ? AnyShapeStyle(Theme.Semantic.record.opacity(0.16)) : AnyShapeStyle(Theme.Brand.softGradient))
                    .frame(width: 104, height: 104)

                Image(systemName: session.isLive ? "eye.fill" : "eye.slash")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(session.isLive ? AnyShapeStyle(Theme.Semantic.record) : AnyShapeStyle(Theme.Brand.gradient))
            }
            .padding(.top, Theme.Space.sm)

            Text(session.isLive ? "Reading your screen" : "Not reading anything")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Text.primary)

            Text(session.isLive
                 ? "The keyboard can answer the message in front of you."
                 : "Turn this on and the keyboard can answer the message in front of you, in any app.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Control

    private var control: some View {
        VStack(spacing: Theme.Space.xs) {
            if session.isLive {
                Button {
                    session.stop()
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Stop")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Semantic.record)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.Semantic.record.opacity(0.14))
                    )
                    .contentShape(Rectangle())
                }
                .pressable()
            } else {
                PrimaryButton(title: "Start screen context", icon: "eye") {
                    store.screenContextAllowed = true
                    session.start()
                }
            }

            // The single most important sentence on the screen.
            Text("iOS shows its own picker and its own recording indicator. This stops when you stop it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Live detail

    private var liveDetail: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    Circle()
                        .fill(Theme.Semantic.record)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Spacer()
                    Text(statusLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                }

                Divider().overlay(Theme.Surface.separator)

                HStack(spacing: 0) {
                    metric(value: "\(session.framesRead)", label: "Frames read")
                    metric(value: "1", label: "Frames stored")
                    metric(value: "0", label: "Frames sent")
                }

                if let context = session.state.context {
                    Divider().overlay(Theme.Surface.separator)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("LAST READ")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.Text.tertiary)

                        HStack(spacing: 5) {
                            Image(systemName: context.appIcon)
                                .font(.system(size: 11))
                            Text(context.sender)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.Text.primary)

                        Text(context.message)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.layoutDirection, context.language.layoutDirection)
                            .frame(maxWidth: .infinity, alignment: context.language.isRightToLeft ? .trailing : .leading)
                    }

                    Button("Show me a different conversation") {
                        session.advanceToNextSample()
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    private var statusLabel: String {
        switch session.state {
        case .off: return ""
        case .starting: return "Starting…"
        case .watching: return "Watching"
        case .ready(let context): return context.appName
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Text.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Explanation

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What actually happens")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    step(
                        number: 1,
                        title: "iOS captures the screen",
                        detail: "You pick what to share in Apple's own picker. Capture keeps running when you switch to WhatsApp or Slack."
                    )
                    step(
                        number: 2,
                        title: "Text is read on device",
                        detail: "Each frame goes through on-device text recognition. The frame is overwritten by the next one and never saved."
                    )
                    step(
                        number: 3,
                        title: "Only text reaches the keyboard",
                        detail: "The keyboard receives the recognised message, not an image, and only when you tap Reply."
                    )
                }
            }
        }
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Text.onBrand)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.Brand.gradient))

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

    // MARK: Limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What it will not do")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    limit("Run forever. Apple reserves permanent capture for remote-desktop apps, so every session is one you started.")
                    limit("See protected content. Banking and video apps can black themselves out of any recording, and they do.")
                    limit("Work in the background silently. iOS shows a recording indicator the entire time, and so does the keyboard.")
                }
            }
        }
    }

    private func limit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Text.tertiary)
                .frame(width: 14, height: 18)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cloud toggle

    private var cloudToggle: some View {
        Card {
            ToggleRow(
                title: "Use the cloud for replies",
                subtitle: "Off keeps the recognised text on the device and uses the smaller local model.",
                icon: "cloud",
                isOn: $store.screenContextCloudReplies
            )
        }
    }
}
