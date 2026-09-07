import SwiftUI
import UIKit

extension KeyboardController {
    func performPress(
        _ cap: KeyCap, at unitPoint: CGPoint?, touchEvidence: KeyTouchEvidence?, playsFeedback: Bool
    ) {
        switch cap {
        case .character(let value):
            insertCharacter(value, at: unitPoint, touchEvidence: touchEvidence, playsFeedback: playsFeedback)
        case .shift:
            toggleShift()
        case .backspace:
            deleteBackward()
        case .plane, .globe, .settings, .emoji, .copyclip, .hideKeyboard:
            performNavigationPress(cap)
        case .space, .ret, .cursorLeft, .cursorRight, .deleteForward:
            performEditingPress(cap)
        case .dictation, .aiReply, .aiFix, .quickTone:
            performActionPress(cap)
        }
    }

    private func performNavigationPress(_ cap: KeyCap) {
        switch cap {
        case .plane(let destination, _):
            if overlay.showsLetterKeys {
                Feedback.modifierPress()
            } else {
                show(.none)
            }
            withAnimation(Theme.Motion.quick) { plane = destination }
        case .globe:
            Feedback.modifierPress()
            advanceLanguage()
        case .settings:
            Feedback.modifierPress()
            onOpenContainingApp?(SharedStore.settingsURL)
        case .emoji:
            show(overlay.isEmoji ? .none : .emoji)
        case .copyclip:
            show(overlay.isCopyClip ? .none : .copyclip)
        case .hideKeyboard:
            Feedback.modifierPress()
            onDismissKeyboard?()
        default:
            return
        }
    }

    private func performEditingPress(_ cap: KeyCap) {
        switch cap {
        case .space:
            insertSpace()
        case .ret:
            insertReturn()
        case .cursorLeft:
            moveCursor(by: -1)
        case .cursorRight:
            moveCursor(by: 1)
        case .deleteForward:
            deleteForward()
        default:
            return
        }
    }

    private func insertReturn() {
        Feedback.keyPress()
        retirePendingAutocorrectUndo(.acceptLearning)
        if !consumeGroupedSkipLearn() { learnWordJustCommitted() }
        commitPendingPersonalToken()
        target?.insertText("\n")
        lastLearnedFolded = nil
        deletedWordPrefix = nil
        armShiftAtBoundary()
        refreshSuggestions()
    }

    private func moveCursor(by offset: Int) {
        Feedback.keyPress()
        deletedWordPrefix = nil
        retirePendingAutocorrectUndo(.acceptLearning)
        target?.adjustTextPosition(byCharacterOffset: offset)
        refreshSuggestions()
    }

    private func deleteForward() {
        if selection != nil {
            deleteBackward()
            return
        }
        guard let first = contextAfter.first else { return }
        target?.adjustTextPosition(byCharacterOffset: String(first).utf16.count)
        deleteBackward()
    }

    private func performActionPress(_ cap: KeyCap) {
        switch cap {
        case .dictation:
            Feedback.actionPress()
            toggleDictation()
        case .aiReply:
            run(.reply)
        case .aiFix:
            run(.fix)
        case .quickTone:
            performQuickTone()
        default:
            return
        }
    }

    private func performQuickTone() {
        Feedback.actionPress()
        switch SuggestionBar.toneTap(hasTextToWorkWith: hasTextToWorkWith, isWorking: isWorking) {
        case .rewrite: runDefaultTone()
        case .needsText: refuseForEmptyField(.rewrite)
        case .ignore: break
        }
    }
}
