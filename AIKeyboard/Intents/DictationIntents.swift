import AIKeyboardCore
import AppIntents
import Foundation

/// Starts a dictation session without the user going to find the app first.
///
/// **The flow this replaces is the worst one in the product.** A keyboard
/// extension cannot open a microphone: `AVAudioSession.setActive(true)` there
/// answers 561145187, `cannotStartRecording`, with Full Access granted and the
/// microphone entitled. So the microphone lives in this app and the transcript
/// crosses the App Group, and nothing in an extension can launch its containing
/// app either. Before this intent, starting a session meant leaving the app you
/// were writing in, finding aBitBetterKeyboard, tapping Start, and switching
/// back. This is that same session start, one press of the Action Button, one
/// Shortcut, or one Spotlight result away.
///
/// **The app is brought to the foreground to start it, and that is a constraint
/// rather than a shortcut taken here.** An app in the *background* cannot begin
/// recording — the same error code — while a session that is already active
/// survives the app switch under the `audio` background mode, which is the whole
/// reason dictation is a session and not a button. `AudioRecordingIntent`
/// (AppIntents, iOS 18) is the one API that lets an intent start recording from
/// the background, and Apple's own documentation attaches a condition this build
/// cannot meet: "you must start a Live Activity when you begin the audio
/// recording and keep it active as long as you record audio. If you don't start
/// a Live Activity, the audio recording stops." A Live Activity needs ActivityKit
/// and a widget extension target, which this project does not have; the protocol
/// also needs iOS 18 against a deployment target of 17. So this foregrounds. An
/// app switch the user asked for and can see is a much better outcome than a
/// shortcut that reports success over a microphone that never opened.
/// `.claude/docs/dictation-front-door.md` records what the background version
/// would cost.
struct StartDictationIntent: AppIntent {

    static var title: LocalizedStringResource = "Start Dictation"

    static var description = IntentDescription(
        "Starts a dictation session, so the microphone key on the keyboard works in whatever app you are writing in.",
        categoryName: "Dictation",
        searchKeywords: ["dictate", "dictation", "voice", "microphone", "speech"])

    /// Deprecated in iOS 26 in favour of `supportedModes`, and kept because this
    /// app deploys to iOS 17, where `IntentModes` does not exist. Apple's own
    /// deprecation note keeps `true` working for an intent that runs inside its
    /// own app, which is this one; the pair below is the only way to say
    /// "foreground me" on both sides of that line.
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dictation = DictationService.shared

        // `start` already returns true for a session that is running, so this
        // branch is about what the user is told rather than about correctness:
        // "already on" and "just started" are different answers to somebody who
        // pressed a button and is about to switch away.
        if dictation.isRunning {
            return .result(
                dialog:
                    "Dictation is already on. Switch to the app you're writing in and tap the microphone key."
            )
        }

        // **No session length, the same as every other door.** This intent briefly
        // read a `SharedStore.dictationSessionMinutes` setting while Home and the
        // deep link passed a literal `0`; the bound came out of all three and the
        // setting was deleted with it, because
        // dictation is something the user starts and stops rather than something
        // that expires under them. `DictationService.noSessionLimit` carries the
        // reasoning and names what `0` actually meant.
        //
        // It matters most here, of the three: this is the one door that opens a
        // microphone from a single press and then leaves the user in another app
        // with no card in front of them saying LIVE. A session that ended on its
        // own would at least fail closed. It does not, so the dialog below is the
        // only thing telling them the microphone is open, which is why it says so
        // plainly rather than reporting success.
        guard await dictation.start(minutes: DictationService.noSessionLimit) else {
            throw DictationIntentError.couldNotStart(dictation.lastError)
        }

        return .result(
            dialog:
                "Dictation is on. Switch to the app you're writing in and tap the microphone key. It stays on until you stop it."
        )
    }
}

/// Ends the session from wherever the user is, without opening the app.
///
/// **This one does not foreground, and the asymmetry with starting is the
/// point.** Stopping opens no microphone, so none of the background rule above
/// applies to it. An intent with no `openAppWhenRun` runs inside this app's own
/// process, and while a session is live that process is already running — the
/// `audio` background mode is what keeps it alive once recording has started —
/// so the `DictationService.shared` reached here is the object actually holding
/// the microphone. Pulling somebody out of WhatsApp to press Stop would undo the
/// thing the start intent exists for.
///
/// With no session running, iOS launches this app in the background to run the
/// intent and `isRunning` is false in that fresh process. "No session" is the
/// true answer there: a session cannot outlive the process that holds the
/// microphone.
struct StopDictationIntent: AppIntent {

    static var title: LocalizedStringResource = "Stop Dictation"

    static var description = IntentDescription(
        "Ends the dictation session and closes the microphone.",
        categoryName: "Dictation",
        searchKeywords: ["dictate", "dictation", "voice", "microphone", "stop"])

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dictation = DictationService.shared
        guard dictation.isRunning else {
            return .result(dialog: "No dictation session is running.")
        }
        dictation.stop()
        return .result(dialog: "Dictation stopped.")
    }
}

/// The one way a dictation intent fails, carrying the reason the service already
/// wrote for the app's own screens.
///
/// A thrown error rather than a cheerful dialog, because Shortcuts shows a
/// failure as a failure and stops the rest of the shortcut: a start that
/// answered "done" over a microphone the user denied would be the silent failure
/// this whole design is arranged to avoid. `DictationService.lastError` is
/// written by the service for `HomeDictationCard`, so it is already user-facing
/// prose and never a raw error code.
enum DictationIntentError: Error, CustomLocalizedStringResourceConvertible {
    case couldNotStart(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .couldNotStart(let reason):
            if reason.isEmpty { return "Dictation couldn't start." }
            return "Dictation couldn't start. \(reason)"
        }
    }
}
