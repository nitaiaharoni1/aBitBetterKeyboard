import SwiftUI
import AIKeyboardCore

// MARK: - Background

/// The flat app surface with a whisper of brand at the top edge. Static on
/// purpose: the old drifting colour blobs cost a 90pt blur and a repeatForever
/// animation on every screen, and motion that communicates nothing is noise.
struct AmbientBackground: View {
    var intensity: Double = 1

    var body: some View {
        Theme.Surface.background
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Theme.Brand.solid.opacity(0.05 * intensity), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 300)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
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
