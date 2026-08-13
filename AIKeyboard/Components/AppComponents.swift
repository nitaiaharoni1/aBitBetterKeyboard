import SwiftUI
import AIKeyboardCore

// MARK: - Background

/// The flat app surface, and nothing else. The old brand whisper at the top
/// edge went with the Warm White / Orange / Graphite direction: orange is
/// reserved for AI moments, primary actions and selection, so the canvas
/// carries no tint at all. Still one named place, so the surface is painted
/// exactly once per screen.
struct AmbientBackground: View {
    var body: some View {
        Theme.Surface.background
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

/// A quiet text control that reveals a paragraph in place. Used on settings
/// that send data off-device or write a file, where a subtitle is not enough
/// and a sheet would be too much.
struct LearnMoreDisclosure: View {
    let detail: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Button {
                withAnimation(Theme.Motion.quick) {
                    isExpanded.toggle()
                }
            } label: {
                Text(isExpanded ? "Show less" : "Learn more")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .padding(.vertical, Theme.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Show less" : "Learn more")

            if isExpanded {
                Text(detail)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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

/// The small square icon tile that leads rows and info blocks. Resting state
/// is the direction's small-icon-button look: a graphite glyph on an inset
/// warm-canvas well with a hairline, matching the field/chip language of
/// `CloudModelFieldSection` and the layout editor. Pass `tint` for state and
/// AI moments — recording red, or brand orange where the row *is* the feature.
struct IconBadge: View {
    let systemName: String
    var tint: Color?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint ?? Theme.Text.primary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.Surface.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.Surface.separator, lineWidth: 1)
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

// MARK: - Graphite hero treatment

extension View {
    /// The top edge of the mock's `.hero-card`: a 1pt white line at 12%,
    /// pulled in past the corner curves so it reads as light catching the
    /// slab's top face. Reserved for the one graphite hero per screen, and
    /// paired with `.ambientDepth()`.
    func graphiteTopHighlight(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        overlay(alignment: .top) {
            Color.white.opacity(0.12)
                .frame(height: 1)
                .padding(.horizontal, cornerRadius)
        }
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
