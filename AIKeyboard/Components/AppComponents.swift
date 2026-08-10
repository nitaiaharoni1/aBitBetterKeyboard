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

// MARK: - StatusCapsule

/// Small filled-capsule label used for status badges: "LIVE", "SAMPLE",
/// "LOW MEMORY", etc.
struct StatusCapsule: View {
    let text: String
    let colour: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Theme.Text.onBrand)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour))
    }
}

// MARK: - IconBadge

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

// MARK: - InfoRow

/// Icon badge + title/detail stack. Used standalone or wrapped in a Card by call sites.
struct InfoRow: View {
    let icon: String
    var tint: Color?
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            IconBadge(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Divider

extension Divider {
    /// A `Divider` tinted with `Theme.Surface.separator`.
    static var themed: some View {
        Divider().overlay(Theme.Surface.separator)
    }
}

// MARK: - Settings link

/// Opens the root of the iOS Settings app.
///
/// `UIApplication.openSettingsURLString` is the only Settings destination iOS
/// offers — there is no constant for a specific sub-screen, so callers that
/// need to guide the user deeper should pair this with numbered instructions.
func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
