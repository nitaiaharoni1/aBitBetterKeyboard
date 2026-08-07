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

    private let features = [
        ("infinity", "Unlimited Fix and Rewrite", "Free stops at 20 a day"),
        ("waveform", "Cloud dictation", "Better in noisy places and on mixed Hebrew and English"),
        ("slider.horizontal.3", "Every tone", "Free includes Clearer only"),
        ("character.book.closed", "Personal dictionary", "Names and terms that survive autocorrect"),
        ("lock.shield", "Nothing kept", "Text is processed and dropped, never stored")
    ]

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(spacing: Theme.Space.lg) {
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
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Space.xs) {
            SparkleMark(size: 40)
                .padding(.top, Theme.Space.sm)

            Text("AI Keyboard Pro")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.Text.primary)

            Text("For people who write all day, in two languages, in somebody else's app.")
                .font(.system(size: 15))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Text.secondary)

                Text(plan.price)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Text.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(plan.note ?? plan.period)
                    .font(.system(size: 12))
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
                        isSelected ? AnyShapeStyle(Theme.Brand.gradient) : AnyShapeStyle(Theme.Surface.separator),
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

            Text(store.isSubscribed ? "Renews \(selectedPlan.price) \(selectedPlan.period)" : "Then \(selectedPlan.price) \(selectedPlan.period) · cancel anytime")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
        }
    }

    private var legal: some View {
        Text("Mock paywall. Nothing is charged and no purchase is made.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.Text.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
