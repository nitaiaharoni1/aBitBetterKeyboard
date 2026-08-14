import SwiftUI
import AIKeyboardCore

struct SubscriptionView: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: Plan = .yearly

    enum Plan: String, CaseIterable, Identifiable {
        case monthly
        case yearly

        var id: String { rawValue }
        var title: String { self == .monthly ? "Monthly" : "Yearly" }
        var price: String { self == .monthly ? "₪24.90" : "₪179" }
        var period: String { self == .monthly ? "per month" : "per year" }
        var note: String? { self == .monthly ? nil : "₪14.90 a month · save 40%" }
    }

    /// A "Cloud dictation" row used to sit second, promising something "better in
    /// noisy places". It was removed when nothing recorded audio anywhere. Dictation
    /// is real now, and the row still does not come back: every transcription in
    /// this product goes to the cloud, because Apple's on-device speech has no
    /// Hebrew, so "cloud dictation" describes the free tier as exactly as it
    /// describes a paid one. And "better in noisy places" is unmeasured — every
    /// clip in `Bar/dictation/` is studio-clean synthetic speech, which the corpus
    /// says in as many words.
    ///
    /// **The two free-tier limits are gone for the same reason, and they were a
    /// worse case.** These rows said "Free stops at 20 a day" and "Free includes
    /// Clearer only". Nothing anywhere counts an action or gates a tone — there is
    /// no meter in `KeyboardController`, and `AIResultPanel` draws all six chips
    /// whatever `isSubscribed` says — so both were describing a restriction the
    /// build does not impose, on the one screen where a claim about what you get
    /// for money is a claim about money. Removed rather than implemented: metering
    /// a mock paywall is a feature nobody asked for, and rather than left inside
    /// the "Mock paywall" framing, which sits below the CTA and off the bottom of
    /// this scroll view while the rows sit above it. The rows now describe the
    /// keyboard as built, and `legal` says plainly that none of it is limited.
    private let features = [
        ("infinity", "Unlimited Fix and Rewrite", "As many as you like, in every language you type in"),
        ("slider.horizontal.3", "Every tone", "Six registers, plus one line you write yourself"),
        ("character.book.closed", "Personal dictionary", "Names and terms that survive autocorrect"),
        ("lock.shield", "Nothing kept", "Text is processed and dropped, never stored")
    ]

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    hero
                    featureList
                    planPicker
                    cta
                    legal
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: "sparkles")
                .font(Theme.Glyph.medium(34))
                .foregroundStyle(Theme.Brand.solid)
                .accessibilityHidden(true)
                .padding(.top, Theme.Space.sm)

            Text("aBitBetterKeyboard Pro")
                .font(Theme.Fonts.display)
                .tracking(-0.5)
                .foregroundStyle(Theme.Text.primary)

            // Said at the top, where the price is, rather than only in the
            // footer a scroll away: this screen charges nothing.
            StatusCapsule(text: "MOCK PAYWALL", colour: Theme.Text.secondary)

            Text("For people who write all day, in two languages, in somebody else's app.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.sm)
    }

    // MARK: Features

    private var featureList: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ForEach(features, id: \.0) { icon, title, detail in
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        IconBadge(systemName: icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(Theme.Fonts.body.weight(.semibold))
                                .foregroundStyle(Theme.Text.primary)
                            Text(detail)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Plans

    private var planPicker: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Plan.allCases) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: Plan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) { selectedPlan = plan }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title)
                    .font(Theme.Fonts.callout.weight(.semibold))
                    .foregroundStyle(Theme.Text.secondary)

                Text(plan.price)
                    .font(Theme.Fonts.title.weight(.bold))
                    .foregroundStyle(Theme.Text.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(plan.note ?? plan.period)
                    .font(Theme.Fonts.micro)
                    .foregroundStyle(plan.note == nil ? Theme.Text.secondary : Theme.Brand.solid)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(Theme.Brand.solid) : AnyShapeStyle(Theme.Surface.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel("\(plan.title), \(plan.price) \(plan.period)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: CTA

    private var cta: some View {
        VStack(spacing: Theme.Space.xs) {
            PrimaryButton(
                title: store.isSubscribed ? "Manage subscription" : "Start 7 days free",
                icon: store.isSubscribed ? nil : "sparkles"
            ) {
                Feedback.success()
                withAnimation { store.isSubscribed.toggle() }
            }

            Text(
                store.isSubscribed
                    ? "Renews \(selectedPlan.price) \(selectedPlan.period)"
                    : "Then \(selectedPlan.price) \(selectedPlan.period) · cancel anytime"
            )
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Text.secondary)
        }
    }

    private var legal: some View {
        Text(
            "Mock paywall. Nothing is charged and no purchase is made. Nothing in the list above is "
                + "limited either, for anyone: there is no free tier for it to be held back from."
        )
        .font(Theme.Fonts.caption)
        .foregroundStyle(Theme.Text.tertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
