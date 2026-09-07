import Foundation

extension ConversationalHebrewModel {
    func validate() -> Bool {
        guard hasValidSectionLengths(), validateVocabulary(), validateAlphabeticalIndexes(),
            validateLengthIndex()
        else { return false }
        var bigramRows = 0
        guard
            validateCSR(
                first: .biFirst, followers: .biFollow, rows: header.vocabularyCount,
                edgeCount: header.bigramEdgeCount, nonemptyRows: &bigramRows),
            bigramRows == header.bigramRowCount,
            validateTrigramKeys()
        else { return false }
        var ignoredRows = 0
        return validateCSR(
            first: .triFirst, followers: .triFollow, rows: header.trigramKeyCount,
            edgeCount: header.trigramEdgeCount, nonemptyRows: &ignoredRows)
    }

    private func hasValidSectionLengths() -> Bool {
        let vocabulary = header.vocabularyCount
        return vocabulary > 0 && vocabulary <= Int(UInt16.max)
            && exactLength(.words, vocabulary, width: 6)
            && exactLength(.counts, vocabulary, width: 4)
            && exactLength(.alpha, vocabulary, width: 4)
            && exactLength(.byLength, vocabulary, width: 4)
            && exactLength(.biFirst, vocabulary + 1, width: 4)
            && exactLength(.biFollow, header.bigramEdgeCount, width: 4)
            && exactLength(
                .triPairs, header.trigramKeyCount, width: header.flags & Self.triPairsU32Flag != 0 ? 4 : 8)
            && exactLength(.triFirst, header.trigramKeyCount + 1, width: 4)
            && exactLength(.triFollow, header.trigramEdgeCount, width: 4)
            && span(.lengthFirst).length >= 8
            && span(.lengthFirst).length % 4 == 0
    }

    private func validateVocabulary() -> Bool {
        var previousCount = UInt32.max
        var previousWord: Int?
        for wordID in 0..<header.vocabularyCount {
            guard let descriptor = wordDescriptor(wordID),
                descriptor.offset <= span(.strings).length,
                descriptor.byteCount <= span(.strings).length - descriptor.offset,
                validUTF8(wordID, expectedCharacters: descriptor.characterCount),
                let count = u32(.counts, wordID),
                count <= previousCount
            else { return false }
            if count == previousCount, let previousWord,
                compareWords(previousWord, wordID) != .orderedAscending
            {
                return false
            }
            previousCount = count
            previousWord = wordID
        }
        return true
    }

    private func validateAlphabeticalIndexes() -> Bool {
        guard validatePermutation(.alpha), validatePermutation(.byLength) else { return false }
        for index in 1..<header.vocabularyCount {
            guard let left = u32(.alpha, index - 1), let right = u32(.alpha, index),
                compareWords(Int(left), Int(right)) == .orderedAscending
            else { return false }
        }
        return true
    }

    private func validateLengthIndex() -> Bool {
        var previous = 0
        for bucket in 0..<(span(.lengthFirst).length / 4) {
            guard let raw = u32(.lengthFirst, bucket) else { return false }
            let next = Int(raw)
            guard next >= previous, next <= header.vocabularyCount else { return false }
            if bucket > 0, !hasWordsOfLength(bucket - 1, from: previous, to: next) { return false }
            previous = next
        }
        return previous == header.vocabularyCount
    }

    private func hasWordsOfLength(_ length: Int, from start: Int, to end: Int) -> Bool {
        for index in start..<end {
            guard let wordID = u32(.byLength, index), wordDescriptor(Int(wordID))?.characterCount == length
            else { return false }
        }
        return true
    }

    private func validateTrigramKeys() -> Bool {
        var previous: UInt64?
        for index in 0..<header.trigramKeyCount {
            guard let pair = trigramPair(at: index) else { return false }
            let first = Int(pair >> 32)
            let second = Int(pair & 0xFFFF_FFFF)
            guard first < header.vocabularyCount, second < header.vocabularyCount,
                previous.map({ $0 < pair }) ?? true
            else { return false }
            previous = pair
        }
        return true
    }
}
