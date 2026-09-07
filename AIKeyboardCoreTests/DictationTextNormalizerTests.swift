import XCTest

@testable import AIKeyboardShared

final class DictationTextNormalizerTests: XCTestCase {
    func testHebrewLoanwordsAcrossMarksAndHorizontalSpaces() {
        for mark in ["'", "׳", "’", "ʼ"] {
            for space in [" ", "  ", "\t", "\u{00A0}", "\u{202F}"] {
                for (left, right) in [("ג", "ף"), ("ג", "ון"), ("ז", "אנר"), ("צ", "יפס"), ("הג", "ירפה")] {
                    check(left + space + mark + space + right, left + mark + right)
                    check(left + space + mark + right, left + mark + right)
                    if left.count > 1 || right.count == 1 {
                        check(left + mark + space + right, left + mark + right)
                    }
                }
            }
        }
    }

    func testAcronymsAreNotLimitedToThreeConsonants() {
        for mark in ["\"", "״", "“", "”"] {
            for (left, right) in [("צה", "ל"), ("רמב", "ם"), ("ד", "ר"), ("מנכ", "ל")] {
                check(left + " " + mark + " " + right, left + mark + right)
                check(left + mark + " " + right, left + mark + right)
                check(left + " " + mark + right, left + mark + right)
            }
        }
    }

    func testEnglishContractionsAndPossessives() {
        for mark in ["'", "’", "ʼ"] {
            for (left, right) in [
                ("don", "t"), ("I", "m"), ("we", "re"), ("they", "ve"), ("she", "ll"), ("he", "d"),
                ("Jeff", "s")
            ] {
                check(left + " " + mark + " " + right, left + mark + right)
                check(left + mark + " " + right, left + mark + right)
                check(left + " " + mark + right, left + mark + right)
            }
        }
    }

    func testMultipleMarksNiqqudEmojiAndMixedLanguages() {
        check("ג ' ף, צ ' יפס וז ' אנר", "ג'ף, צ'יפס וז'אנר")
        check("צ'ופצ ' יק", "צ'ופצ'יק")
        check("צ ' ופצ ' יק", "צ'ופצ'יק")
        check("גֶ ' ף", "גֶ'ף")
        check("👨‍👩‍👧‍👦 ג ' ף: don ' t stop", "👨‍👩‍👧‍👦 ג'ף: don't stop")
        check("צה \" ל ורמב \" ם", "צה\"ל ורמב\"ם")
        check("ג ' ף אמר 'שלום'", "ג'ף אמר 'שלום'")
        check("ג 'ף אמר 'שלום'", "ג'ף אמר 'שלום'")
        check("הוא אמר \"ג ' ף\"", "הוא אמר \"ג'ף\"")
    }

    func testQuotesAbbreviationsAndAmbiguousWordBoundariesStayIntact() {
        for text in [
            "יום ג׳ בשבוע", "ג' כהן", "ר' ישראל", "פרופ' ישראל", "מס' חמש",
            "הוא הציג 'שלום'", "הוא הציג 'שלום עולם'", "הוא הציג ‘שלום עולם’",
            "הוא הציג 'שלום!'", "הוא הציג 'שלום 123'", "הוא הציג 'שלום 🙂'",
            "הוא הציג ‘שלום!’", "הוא הציג \"ל!\"", "הוא הציג “ל!”",
            "הוא אמר \"ל\"", "הוא אמר “שלום עולם”", "say 'hello world'", "say 's'",
            "5 ' 10", "rock ' n ' roll", "dogs ' cats", "foo ' bar", "ג ' Jeff",
            "garden ' t", "apple ' re", "table ' ve",
            "don\n' t", "ג\n' ף", "ג ' \nף", "ג\r\n' ף", "ג'", "ג ' ",
            "ג'ף", "צ׳יפס", "צה״ל", "don't", "one - two", "10 : 30", "bonjour !", ""
        ] {
            check(text, text)
        }
    }

    func testRepeatedRepairsAndArbitraryNeighborsPreserveText() {
        for mark in ["'", "׳", "’", "ʼ"] {
            let fragment = "צ \(mark) ופצ \(mark) יק"
            let repaired = "צ\(mark)ופצ\(mark)יק"
            check(
                Array(repeating: fragment, count: 100).joined(separator: ", "),
                Array(repeating: repaired, count: 100).joined(separator: ", "))
        }
        let neighbors = ["ג", "ף", "don", "t", "🙂", "'", "ʼ", "\"", "גֶ", "123", "\n", "שלום!"]
        for left in neighbors {
            for right in neighbors {
                let input = left + " ג ' ף " + right
                let actual = DictationTextNormalizer.normalize(input)
                XCTAssertEqual(
                    actual.replacingOccurrences(of: " ", with: ""),
                    input.replacingOccurrences(of: " ", with: ""))
                XCTAssertEqual(DictationTextNormalizer.normalize(actual), actual)
            }
        }
    }

    private func check(
        _ input: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = DictationTextNormalizer.normalize(input)
        XCTAssertEqual(actual, expected, input.debugDescription, file: file, line: line)
        XCTAssertEqual(
            DictationTextNormalizer.normalize(actual), actual, "not idempotent: \(input.debugDescription)",
            file: file, line: line)
    }
}
