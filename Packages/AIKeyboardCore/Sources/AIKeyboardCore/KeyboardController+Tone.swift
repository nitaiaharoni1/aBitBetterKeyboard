import Foundation
import SwiftUI

extension KeyboardController {

    // MARK: Tone selection

    public func selectTone(_ tone: ToneStyle) {
        Feedback.modifierPress()
        aiSourceText = aiSourceText.isEmpty ? aiTargetText : aiSourceText
        runTone(.builtIn(tone))
    }

    /// The registers a long press on the one-tap rewrite key offers, in the order
    /// the popup draws them.
    ///
    /// **The default leads, because index 0 of an alternates popup is the no-op.**
    /// `KeyView` treats lifting on the first item as "the long press changed
    /// nothing", which for a letter means the character it already inserted. The
    /// same rule has to hold here or a user who holds the key, looks, and lifts
    /// without moving gets a register they did not pick — so the first item is
    /// what a plain tap would have run.
    ///
    /// The user's own tone sits second when it is *selected* and is not already the
    /// default. Written but switched off is deliberately absent: `ToneSetting` only
    /// resolves to `.custom` when `prefersCustomTone` is on, so with the switch off
    /// there is no instruction to send and the entry would be a name drawn over the
    /// built-in register standing behind it. `AIResultPanel.toneChips` draws its
    /// custom chip on exactly the same condition, and the two surfaces disagreeing
    /// about which registers exist is drift this repo has shipped once already.
    /// It cannot be a seventh `ToneStyle` either: that enum's raw values are the
    /// persisted setting. See `ToneSetting`.
    ///
    /// Read through the store rather than off a published copy, for the reason
    /// `defaultTone` gives — Settings is a different process.
    public var toneAlternates: [String] {
        let setting = store.toneSetting
        var titles = [setting.title]
        if setting.instruction == nil, customTone != nil { titles.append(ToneSetting.customTitle) }
        titles += ToneStyle.allCases.map(\.title).filter { $0 != setting.title }
        return titles
    }

    /// Runs one of `toneAlternates` by the name the popup drew.
    ///
    /// By title rather than by index, because the popup and the controller would
    /// otherwise have to agree about an ordering that `toneAlternates` builds from
    /// a stored setting — and they would disagree the moment the default tone
    /// changed between the key being drawn and the finger lifting.
    ///
    /// The same two refusals as `runDefaultTone`: nothing to rewrite is a key that
    /// should not have fired, and a call in flight must not be thrown away by a
    /// second one.
    public func selectTone(named title: String) {
        // A call in flight stays a silent ignore: the button is showing a spinner,
        // so the tap has already been answered. An empty field has not been.
        guard !isWorking else { return }
        guard hasTextToWorkWith else {
            refuseForEmptyField(.rewrite)
            return
        }
        if title == ToneSetting.customTitle, let custom = customTone {
            selectTone(custom)
            return
        }
        guard let tone = ToneStyle.allCases.first(where: { $0.title == title }) else { return }
        selectTone(tone)
    }

    /// The same, for the tone the user wrote. The panel's seventh chip.
    public func selectTone(_ setting: ToneSetting) {
        Feedback.modifierPress()
        aiSourceText = aiSourceText.isEmpty ? aiTargetText : aiSourceText
        runTone(setting)
    }

    /// The user's own tone, or nil when they have not written one. The tone panel
    /// shows a chip for it only when there is one to show.
    public var customTone: ToneSetting? {
        let setting = store.toneSetting
        return setting.instruction == nil ? nil : setting
    }

    /// The tone the one-tap rewrite would run in right now.
    ///
    /// Read out of `UserDefaults` on every call rather than off a cached copy, and
    /// that goes for all three halves of it: Settings lives in the other process,
    /// the App Group is how a change gets here, and `SharedStore.load()` fills the
    /// `@Published` properties once at launch. A keyboard already on screen when
    /// the tone changed would otherwise answer with the one that was stored when
    /// it started. See `SharedStore.storedDefaultTone`.
    public var defaultTone: ToneSetting { store.toneSetting }

    /// Rewrite what the user has typed, in their default tone, straight from the
    /// suggestion bar — no menu, and no register to pick.
    ///
    /// **Rewrite rather than Fix, and the defect's own words decide it.** D6 asks
    /// for a quick action "that is logic is by our default tone", and a tone is
    /// exactly what Fix has none of: `Prompts.fix` rule 5 keeps the writer's
    /// register on purpose, and `EditScope` undoes any change the model cannot name
    /// as a mistake. Pointing a default tone at Fix would leave it with nothing to
    /// do. Rewrite is also the action the extra tap actually costs something on —
    /// Fix opens, runs and shows one answer, while Rewrite makes the user choose a
    /// register first, which is the decision a default is for. This is additionally
    /// the first code in the build that reads `SharedStore.defaultTone` at all; the
    /// setting existed, the app wrote it, and nothing had ever consulted it.
    ///
    /// The two refusals are separate on purpose. Nothing to work with is not an
    /// error, it is a button that should not have fired; a call already in flight
    /// is refused because `beginWork` cancels its predecessor, so a second tap
    /// would silently throw away the answer the first one is waiting for.
    public func runDefaultTone() {
        // A call in flight stays a silent ignore: the button is showing a spinner,
        // so the tap has already been answered. An empty field has not been.
        guard !isWorking else { return }
        guard hasTextToWorkWith else {
            refuseForEmptyField(.rewrite)
            return
        }
        Feedback.actionPress()
        // The same first move `run(_:)` makes, and it has to be made here too: the
        // bar enters this with no menu in front of it, so nothing has refreshed the
        // sentence being worked on. `selectTone` deliberately keeps whatever is
        // already in `aiSourceText`, which after an earlier action is the
        // *previous* sentence — and `replaceTargetText` then deletes that many
        // characters out of the new one.
        aiSourceText = aiTargetText
        runTone(store.toneSetting)
    }

    /// One tone call, however the tone was chosen.
    ///
    /// `selectedTone` stays a `ToneStyle` because that is what the six chips
    /// compare against and what `RewriteVariant` is tagged with; a custom tone is
    /// reported separately rather than by widening it, so nothing downstream has
    /// to change to keep working.
    func runTone(_ setting: ToneSetting) {
        let tone = setting.style
        let instruction = setting.instruction
        selectedTone = tone
        selectedToneIsCustom = instruction != nil
        let source = aiSourceText
        // **One home now.** This used to compute a destination, because the same
        // call could be started from the action row (answer belongs in the banner)
        // or from a panel of tone chips the user was standing in (taking it away
        // under them would be a screen that vanishes when you use it). That panel is
        // deleted, so there is one place an answer can go and no choice to make.
        beginWork(.rewrite, showing: .none) { [engine] in
            try await engine.variants(for: source, tone: tone, instruction: instruction)
        } apply: { controller, variants in
            controller.variants = variants
        }
    }
}
