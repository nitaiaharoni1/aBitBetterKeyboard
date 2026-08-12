import AVFoundation
import Foundation
import Speech

// Runs Apple's own dictation model over `Bar/dictation/audio/` and writes the
// same JSON shape `cloud_outputs.json` uses, so `score.py` grades both with one
// scorer and the numbers are comparable line for line.
//
// **This is the live half of dictation, not the transcriber of record.** The
// keyboard shows these words while somebody is speaking and `CloudDictation`
// replaces them the moment they stop — see `LiveTranscriber`. What the score is
// for is knowing how wrong the draft is, and in particular the one number a word
// error rate cannot see: whether an English word inside a Hebrew sentence comes
// back as `sync` or as `סקין`.
//
// It compiles for the **iOS Simulator** and runs there, for the reason
// `Bar/typing/harness/main.swift` does: `DictationTranscriber` is an iOS API and
// there is no macOS equivalent that would be measuring the shipping path.
//
// The model is downloaded on first run through `AssetInventory`, which is the
// same call `LiveTranscriber.prepare(locale:)` makes in the app.

@available(iOS 26.0, *)
actor Collected {
    var text = ""
    func add(_ piece: String) { text += piece }
}

@available(iOS 26.0, *)
func install(_ locale: Locale) async {
    let module = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
    guard await AssetInventory.status(forModules: [module]) != .installed else { return }
    FileHandle.standardError.write("installing \(locale.identifier(.bcp47))...\n".data(using: .utf8)!)
    if let request = try? await AssetInventory.assetInstallationRequest(supporting: [module]) {
        try? await request.downloadAndInstall()
    }
}

/// One clip, transcribed the way the app transcribes a live utterance: fed in
/// chunks through `SpeechAnalyzer`, taking the finalized results.
@available(iOS 26.0, *)
func transcribe(_ url: URL, locale: Locale) async -> String {
    let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
        let file = try? AVAudioFile(forReading: url),
        let converter = AVAudioConverter(from: file.processingFormat, to: format)
    else { return "" }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    let collected = Collected()
    let reader = Task {
        do {
            for try await result in transcriber.results where result.isFinal {
                await collected.add(String(result.text.characters))
            }
        } catch {
            await collected.add("<error \(error)>")
        }
    }
    do { try await analyzer.start(inputSequence: stream) } catch { return "<start failed>" }

    // Fed in 4,096-frame chunks rather than as one buffer, because that is the
    // shape the audio tap delivers and a transcriber that only ever saw whole
    // files would not be measuring the streaming path.
    let chunk: AVAudioFrameCount = 4096
    while true {
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
            (try? file.read(into: input)) != nil, input.frameLength > 0
        else { break }
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        guard
            let out = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024)
        else { break }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if error == nil, out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
    }
    continuation.finish()
    try? await analyzer.finalizeAndFinishThroughEndOfInput()
    _ = await reader.result
    return await collected.text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func run() async {
    guard #available(iOS 26.0, *) else {
        FileHandle.standardError.write("needs iOS 26\n".data(using: .utf8)!)
        exit(1)
    }
    let bar = URL(fileURLWithPath: CommandLine.arguments[1])
    let out = URL(fileURLWithPath: CommandLine.arguments[2])
    let truth =
        try! JSONSerialization.jsonObject(
            with: Data(contentsOf: bar.appendingPathComponent("ground-truth.json"))) as! [String: Any]
    let clips = truth["clips"] as! [[String: Any]]

    // **A Hebrew clip is transcribed with the Hebrew model and a code-switched
    // one with the Hebrew model too**, because that is what the app does: the
    // locale comes from the keyboard's active layout, and somebody typing Hebrew
    // with English words in it is on the Hebrew layout. Transcribing `he-en` with
    // `en-US` would measure a configuration the product never runs.
    for locale in [Locale(identifier: "en-US"), Locale(identifier: "he-IL")] {
        await install(locale)
    }

    var results: [[String: Any]] = []
    for clip in clips {
        let id = clip["id"] as! String
        let mix = clip["language_mix"] as! String
        let locale = Locale(identifier: mix == "en" ? "en-US" : "he-IL")
        let file = bar.appendingPathComponent(clip["file"] as! String)
        let text = await transcribe(file, locale: locale)
        FileHandle.standardError.write("\(id): \(text)\n".data(using: .utf8)!)
        results.append([
            "id": id,
            "language_mix": mix,
            "config": "apple DictationTranscriber progressiveLongDictation \(locale.identifier)",
            "seconds": clip["duration_seconds"] ?? 0,
            "speech": "yes",
            "languages": locale.identifier,
            "text": text
        ])
    }
    let data = try! JSONSerialization.data(
        withJSONObject: results, options: [.prettyPrinted, .withoutEscapingSlashes])
    try! data.write(to: out)
    FileHandle.standardError.write("wrote \(out.path)\n".data(using: .utf8)!)
}

let done = DispatchSemaphore(value: 0)
Task {
    await run(); done.signal()
}
done.wait()
