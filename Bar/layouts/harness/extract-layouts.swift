// Reads Apple's own keyboard data on this machine and writes
// `Bar/layouts/apple-layouts.json`, the artifact `LayoutProvenanceTests` holds
// every shipped layout against.
//
// Two sources, because they answer two different questions.
//
//   1. `TISCreateInputSourceList` + `UCKeyTranslate` over the macOS input source
//      named for the language gives the *arrangement*: which letter is on which
//      key, for the three letter rows, on the base, shift and option layers.
//
//   2. `InputMode_<tag>.plist` inside the iOS Simulator runtime gives what a
//      *phone* does with that language: the default input mode, and its
//      `SWLayouts` — the software layouts iOS offers, most preferred first.
//
// The second is here because the two disagree and the disagreement is not
// noise. `InputMode_sl.plist` says `Hardware.Layout = "Slovenian"` and
// `SWLayouts[0] = "QWERTZ"` in the same file: Apple ships Slovene a QWERTY
// hardware layout and a QWERTZ software one. This product is a software
// keyboard, so `SWLayouts[0]` wins, and the tool records both so the choice
// stays checkable.
//
// Read `SWLayouts` off the *default* input mode, never off the bundle's first.
// `InputMode_nl.plist` carries two, `nl_NL` and `nl_BE`, and the Belgian one
// leads with AZERTY; taking the first mode in the file says Dutch is AZERTY,
// which it is not.
//
// REGENERATING NEEDS macOS, and it needs the input sources installed. A layout
// this machine does not have is skipped and named in `missing`, so a short run
// is visible rather than silent. Run `Bar/layouts/harness/run.sh`.

import Carbon
import Foundation

// MARK: - Apple's macOS layout data

/// The three letter rows by virtual key code, in the order they sit on the
/// keyboard. A phone keeps the keys in these rows that produce a letter — which
/// is what turns a desktop 12 / 11 / 10 into English's 10 / 9 / 7 without
/// anybody choosing what to drop — so these are the codes and no others.
let letterRowKeys: [[Int]] = [
    [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30],
    [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
    [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]
]

/// The two keys just outside those rows that some layouts put a letter on: on an
/// ISO keyboard 42 sits at the end of the home row and 50 at the start of the
/// bottom one. Recorded so a shipped layout that borrows from them can say where
/// the letter came from.
let adjacentKeys: [Int] = [42, 50]

let shiftModifier = UInt32((shiftKey >> 8) & 0xFF)
let optionModifier = UInt32((optionKey >> 8) & 0xFF)

let letterCategories: Set<Unicode.GeneralCategory> = [
    .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
    .nonspacingMark, .spacingMark, .enclosingMark
]

func isLetter(_ text: String) -> Bool {
    guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else {
        return false
    }
    return letterCategories.contains(scalar.properties.generalCategory)
}

func translate(_ layout: UnsafePointer<UCKeyboardLayout>, key: Int, modifiers: UInt32) -> String {
  var deadKeyState: UInt32 = 0
  var characters = [UniChar](repeating: 0, count: 8)
  var length = 0

  // Three passes, and the third is not belt and braces.
  //
  // A dead key produces nothing on `kUCKeyActionDown` however the flags are set:
  // it arms a state and waits for the next keystroke. Apple's `Hindi – InScript`
  // puts the virama on one — pressing it and then a consonant is how a conjunct
  // is typed — so the first two passes return "" and the row comes out one key
  // short, silently. `kUCKeyActionDisplay` asks what the key *shows*, which is
  // the character it stands for, and that is what a phone key cap has to be.
  for (action, options) in [
    (kUCKeyActionDown, UInt32(kUCKeyTranslateNoDeadKeysBit)),
    (kUCKeyActionDown, UInt32(0)),
    (kUCKeyActionDisplay, UInt32(kUCKeyTranslateNoDeadKeysBit))
  ] {
    deadKeyState = 0
    let status = UCKeyTranslate(
      layout, UInt16(key), UInt16(action), modifiers,
      UInt32(LMGetKbdType()), options, &deadKeyState, 8, &length, &characters)
    if status == noErr, length > 0 {
      return String(utf16CodeUnits: characters, count: length)
    }
  }
  return ""
}

func layoutData(named wanted: String) -> Data? {
    let sources =
        TISCreateInputSourceList(
            [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary, true)?
        .takeRetainedValue() as? [TISInputSource] ?? []
    for source in sources {
        guard let namePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            continue
        }
        let name = Unmanaged<CFString>.fromOpaque(namePointer).takeUnretainedValue() as String
        guard name == wanted else { continue }
        guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
    }
    return nil
}

struct AppleLayout {
    var base: [String] = []
    var shift: [String] = []
    var option: [String] = []
    var adjacent: [String: String] = [:]
}

func readLayout(named name: String) -> AppleLayout? {
    guard let data = layoutData(named: name) else { return nil }
    var result = AppleLayout()
    data.withUnsafeBytes { raw in
        let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
        for keys in letterRowKeys {
            result.base.append(
                keys.map { translate(layout, key: $0, modifiers: 0) }
                    .filter(isLetter).joined())
            result.shift.append(
                keys.map { translate(layout, key: $0, modifiers: shiftModifier) }
                    .filter(isLetter).joined())
            result.option.append(
                keys.map { translate(layout, key: $0, modifiers: optionModifier) }
                    .filter(isLetter).joined())
        }
        for key in adjacentKeys {
            for (label, modifiers) in [("", UInt32(0)), ("shift", shiftModifier)] {
                let produced = translate(layout, key: key, modifiers: modifiers)
                guard isLetter(produced) else { continue }
                result.adjacent["\(key)\(label.isEmpty ? "" : "+" + label)"] = produced
            }
        }
    }
    return result
}

// MARK: - Apple's iOS software-layout data

/// The iOS Simulator runtime root, which is where `InputMode_<tag>.plist` lives.
func runtimeRoot() -> String? {
    if let override = ProcessInfo.processInfo.environment["IOS_RUNTIME_ROOT"] { return override }
    let bases = [
        "/Library/Developer/CoreSimulator/Volumes",
        "/Library/Developer/CoreSimulator/Profiles/Runtimes"
    ]
    let manager = FileManager.default
    for base in bases {
        guard let found = manager.enumerator(atPath: base) else { continue }
        for case let path as String in found where path.hasSuffix("Contents/Resources/RuntimeRoot") {
            let full = base + "/" + path
            if manager.fileExists(atPath: full + "/System/Library/TextInput") { return full }
        }
    }
    return nil
}

struct SoftwareLayout {
    let inputMode: String
    let layouts: [String]
    let hardware: String?
}

func softwareLayout(tag: String, root: String) -> SoftwareLayout? {
    let bundleTag = tag.replacingOccurrences(of: "-", with: "_")
    let path = "\(root)/System/Library/TextInput/TextInput_\(bundleTag).bundle/InputMode_\(bundleTag).plist"
    guard let data = FileManager.default.contents(atPath: path),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any],
        let supported = plist["UIKeyboardSupportedInputModes"] as? [String: Any]
    else { return nil }

    // The default mode for this language, never the first key in the file:
    // `InputMode_nl.plist` holds nl_NL and nl_BE, and only one of them is Dutch.
    let defaults = plist["UIKeyboardDefaultLanguageInputModes"] as? [String: [String]] ?? [:]
    let mode =
        defaults[bundleTag]?.first
        ?? defaults[tag]?.first
        ?? supported.keys.sorted().first(where: { $0.hasPrefix(bundleTag) })
        ?? supported.keys.sorted().first
    guard let mode, let entry = supported[mode] as? [String: Any] else { return nil }
    return SoftwareLayout(
        inputMode: mode,
        layouts: entry["SWLayouts"] as? [String] ?? [],
        hardware: (entry["Hardware"] as? [String: Any])?["Layout"] as? String)
}

// MARK: - The catalogue this repository ships

/// (catalogue id, macOS input source, BCP-47 tag).
///
/// Slovene is the one row whose source is not named for the language: macOS has
/// a `Slovenian` layout and it is QWERTY, while `InputMode_sl.plist` gives
/// `SWLayouts[0] = "QWERTZ"` and names it `QWERTZ-Croatian` on iPad. A software
/// keyboard follows the software layout, so the snapshot records Croatian's
/// arrangement — and `iosHardwareLayout` in the output still says `Slovenian`,
/// so the disagreement stays visible rather than being papered over here.
///
/// **The source name is the load-bearing column.** This machine ships `Czech`
/// *and* `Czech – QWERTY`, `Slovak` and `Slovak – QWERTY`, `Hungarian` and
/// `Hungarian – QWERTY`; naming the wrong one extracts a real Apple layout that
/// is the wrong layout for the language, which is how three keyboards shipped
/// with y and z transposed. Where Apple offers a pair, the one *without* a
/// qualifier is the national arrangement.
let catalogue: [(id: String, source: String, tag: String)] = [
    ("english", "U.S.", "en"), ("hebrew", "Hebrew", "he"), ("russian", "Russian", "ru"),
    ("albanian", "Albanian", "sq"), ("arabic", "Arabic", "ar"), ("azerbaijani", "Azeri", "az"),
    ("belarusian", "Belarusian", "be"), ("bulgarian", "Bulgarian – Standard", "bg"),
    ("catalan", "Spanish", "ca"), ("croatian", "Croatian – QWERTZ", "hr"),
    ("czech", "Czech", "cs"), ("danish", "Danish", "da"), ("dhivehi", "Dhivehi", "dv"),
    ("dutch", "Dutch", "nl"), ("estonian", "Estonian", "et"), ("faroese", "Faroese", "fo"),
    ("filipino", "ABC", "fil"), ("finnish", "Finnish", "fi"), ("french", "French", "fr"),
    ("georgian", "Georgian – QWERTY", "ka"), ("german", "German", "de"), ("greek", "Greek", "el"),
    ("haitian", "Haitian Creole", "ht"), ("hausa", "Hausa", "ha"),
    ("hawaiian", "Hawaiian", "haw"), ("hindi", "Hindi – InScript", "hi"),
    ("hungarian", "Hungarian", "hu"), ("icelandic", "Icelandic", "is"), ("igbo", "Igbo", "ig"),
    ("indonesian", "ABC", "id"), ("irish", "Irish – Extended", "ga"), ("italian", "Italian", "it"),
    ("kyrgyz", "Kyrgyz", "ky"), ("latvian", "Latvian", "lv"),
    ("lithuanian", "Lithuanian – QWERTY", "lt"), ("macedonian", "Macedonian", "mk"),
    ("malay", "ABC", "ms"), ("maltese", "Maltese", "mt"), ("maori", "Māori", "mi"),
    ("marathi", "Marathi – InScript", "mr"), ("nepali", "Nepali – InScript", "ne"),
    ("norwegian", "Norwegian", "nb"), ("pashto", "Afghan Pashto", "ps"),
    ("persian", "Persian – Standard", "fa"), ("polish", "Polish", "pl"),
    ("portuguese", "Portuguese", "pt"), ("romanian", "Romanian – Standard", "ro"),
    ("samoan", "Samoan", "sm"), ("serbian", "Serbian", "sr"),
    ("serbianLatin", "Serbian (Latin)", "sr-Latn"), ("slovak", "Slovak", "sk"),
    ("slovenian", "Croatian – QWERTZ", "sl"), ("spanish", "Spanish", "es"),
    ("swahili", "ABC", "sw"), ("swedish", "Swedish", "sv"), ("tajik", "Tajik (Cyrillic)", "tg"),
    ("tamil", "Tamil99", "ta"), ("tongan", "Tongan", "to"), ("turkish", "Turkish Q", "tr"),
    ("turkmen", "Turkmen", "tk"), ("ukrainian", "Ukrainian", "uk"), ("urdu", "Urdu", "ur"),
    ("welsh", "Welsh", "cy"), ("yoruba", "Yoruba", "yo")
]

// MARK: - Write

let root = runtimeRoot()
var entries: [[String: Any]] = []
var missing: [String] = []

for language in catalogue {
    guard let apple = readLayout(named: language.source) else {
        missing.append("\(language.id): no macOS input source named “\(language.source)”")
        continue
    }
    var entry: [String: Any] = [
        "id": language.id,
        "tag": language.tag,
        "macSource": language.source,
        "base": apple.base,
        "shift": apple.shift,
        "option": apple.option,
        "adjacent": apple.adjacent
    ]
    if let root, let software = softwareLayout(tag: language.tag, root: root) {
        entry["iosInputMode"] = software.inputMode
        entry["iosSoftwareLayouts"] = software.layouts
        if let hardware = software.hardware { entry["iosHardwareLayout"] = hardware }
    }
    entries.append(entry)
}

let document: [String: Any] = [
    "generated": ISO8601DateFormatter().string(from: Date()),
    "iosRuntimeRoot": root ?? "not found",
    "note":
        "Written by Bar/layouts/harness/extract-layouts.swift. base/shift/option are the "
        + "letters Apple's macOS layout produces on the three letter rows, punctuation keys "
        + "dropped. iosSoftwareLayouts is SWLayouts for the language's default input mode, "
        + "most preferred first.",
    "missing": missing,
    "languages": entries
]

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "apple-layouts.json"
let json = try JSONSerialization.data(
    withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try json.write(to: URL(fileURLWithPath: output))
FileHandle.standardError.write(
    Data("wrote \(entries.count) languages to \(output), \(missing.count) missing\n".utf8))
for line in missing { FileHandle.standardError.write(Data("  \(line)\n".utf8)) }
