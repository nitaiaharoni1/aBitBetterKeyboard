import Foundation

// MARK: - Prompt

/// The screen-reading prompt, kept beside the engine and versioned with it
/// because every line of it was bought with a measurement.
///
/// Two things here are load-bearing and look like style if you do not know the
/// history:
///
/// 1. **`messages` is a list, and it comes first.** Every wrong answer measured
///    on the bar was the model picking a bubble one to four positions above the
///    newest, not misreading pixels. Forcing it to enumerate every bubble before
///    naming one turns "which is newest" from a judgement into an index.
///    Re-measured 2026-08-08 with both sides run in one sitting
///    (`Bar/screen-context/ablation/enumerate.json`): dropping the list costs 2
///    points of sender, 3 of keyboard language and four of the near-misses, and
///    lets a trap through that never appears with it. This comment used to claim
///    21/30 → 29/30; the direction and the reason held, the magnitude did not.
/// 2. **`script` and `language` are separate questions, and this is the big
///    one.** Collapsing them scores **22/30** keyboard language against 30/30
///    (`ablation/split.json`) — eight points, far outside the ±1 the model moves
///    between two runs of one configuration. A Hebrew sentence borrowing English
///    words is *mixed* on screen and *Hebrew* to answer, and the keyboard needs
///    the second answer.
///
/// Two rules were tried and measured *worse*, so they are deliberately absent:
/// a paragraph explaining bubble tint and edge (cost 4 points and made repeat
/// runs disagree), and "a printed name always means the message is incoming"
/// (gained 1 point of message accuracy, lost 3 of sender).
///
/// **`language` still offers the model two words, and the keyboard now draws
/// fourteen. That gap is deliberate and it is not free.** Widening the two field
/// descriptions is one edit; what it costs is the whole recorded corpus. Every
/// answer in `Bar/screen-context/cloud_outputs.json` was bought with *these*
/// bytes, `ScreenContextBarTests` replays that file to score the shipping path,
/// and `.claude/CLAUDE.md` is explicit that a delta measured against a recording
/// from another day is not a delta at all — two runs a day apart disagreed on
/// roughly a third of the corpus, against 2 of 30 minutes apart. So changing the
/// prompt without re-recording moves the thing being measured and the measuring
/// stick in the same commit, and there is no dated model version to pin either
/// to. Whoever changes it owes, in one sitting: a fresh `cloud_outputs.json` and
/// `cloud_outputs_repeat.json` from `harness/vertex_vision.py`, the score from
/// `harness/score_cloud.py`, the `ablation/split.json` baseline re-taken by
/// `harness/ablate.py` (the script/language split is worth 8 points and is the
/// most likely thing a rewording breaks), and a re-run of
/// `ScreenContextBarTests` against the new recording. The corpus is 30 frames of
/// English, Hebrew and mixed, so it cannot show the gain either — new frames in
/// a third script are owed with it.
///
/// Until then the widening lives entirely in `parse`, where it can be proved
/// rather than sampled: a message the model does not call Hebrew or English is
/// mapped by its script instead of being called English, and the model's own
/// answer is matched against all fourteen identifiers in case it volunteers one.
enum ScreenPrompt {

    static let instructions = """
        You are looking at a screenshot of a phone messaging app.

        STEP 1. List EVERY message bubble on screen, top to bottom, in `messages`.
        Include bubbles that carry no text of their own: voice notes, images,
        stickers, files, call notices. Include the last bubble even if it is only
        partly visible.

        Do NOT list app chrome as a message: status bar, navigation bar, contact
        name, "online"/"typing…", date dividers, unread dividers, encryption
        notices, reaction or tapback pills, the text input placeholder, and
        bubble timestamps.
        A reply bubble that quotes an earlier message is ONE entry. Its text is
        ONLY the new text below the quote. The quoted part is a copy of something
        already said, set off by an accent bar, a tint, or a smaller font, and it
        must not appear in the entry's text at all.

        STEP 2. Take the LAST entry in your list whose from is "them". That one,
        and only that one, is the answer.

          - If its kind is "text", report its sender and text. `sender` must be a
            name: in a one-to-one chat that is the contact name from the
            navigation bar, never blank.
          - If its kind is anything else, there is nothing to reply to: return
            null for sender, message, script and language. Do NOT fall back to an
            earlier text message. The owner has already moved past it, so
            answering it would be stale.
          - If no entry has from "them", return null as well.

        Never pick an earlier message because it reads as more answerable. The
        last one is the answer even when it is a statement and an earlier one is
        a question.

        Transcription rules for the reported message:
          - Copy it exactly. Do not translate, correct, or re-spell anything.
          - A time or number inside the text is part of the text. Only the
            timestamp attached to the bubble is chrome.
          - An @mention at the start is part of the text, not a sender label.
          - Emoji inside the message body stay. A reaction pill hanging off the
            bubble corner is not part of it.
          - In a right-to-left message, report logical reading order: a full stop
            or comma rendered at the left edge of a line closes the sentence
            before it, so it belongs at the END of that sentence.
        """

    static let task = "Read the screenshot and report the newest message worth replying to."

    /// Order matters and is not alphabetical: enumerate, then transcribe, then
    /// classify. Every later field is decided with the list already written.
    static let fields: [CloudField] = [
        CloudField(
            "messages",
            "Every message bubble on screen, top to bottom.",
            items: [
                CloudField(
                    "from",
                    "\"them\" if someone else sent it, \"me\" if the phone's owner did. The owner's messages are usually aligned to the opposite side from everyone else's and often carry read receipts (checkmarks)."
                ),
                CloudField(
                    "kind",
                    "One of text, voice, image, sticker, file, system. \"text\" only if the bubble's own content is words you can read. A voice note is \"voice\" even though a duration is printed on it. An image with a caption under it is \"image\"; the caption is its own \"text\" entry."
                ),
                CloudField(
                    "sender",
                    "Who sent that bubble, by name. A group chat prints a name above each incoming bubble: use it. A one-to-one chat prints no name at all, because the contact's name sits in the navigation bar at the top of the screen: use that instead. Never leave this empty for a bubble from \"them\"."
                ),
                CloudField(
                    "text",
                    "The words in the bubble, exactly as written, wrapped lines joined with a single space. null when kind is not \"text\"."
                )
            ]),
        CloudField("sender", "The sender of the chosen message, or null."),
        CloudField("message", "The text of the chosen message, or null."),
        CloudField(
            "script",
            "What is physically on screen: \"hebrew\" for Hebrew letters, \"latin\" for Latin letters, \"mixed\" when it genuinely contains both, which includes a Hebrew sentence with English words embedded in it. Null when there is no message."
        ),
        CloudField(
            "language",
            "A different question: which keyboard opens to reply. A Hebrew sentence that borrows English words is answered in Hebrew, so its language is \"hebrew\" while its script is \"mixed\". Only a message actually written in English gets \"english\". Null when there is no message."
        )
    ]
}
