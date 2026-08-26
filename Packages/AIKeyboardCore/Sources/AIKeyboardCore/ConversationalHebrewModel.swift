import Darwin
import Foundation
import os

/// File-backed Hebrew surface forms and exact one-word and two-word continuations.
///
/// The AKN1 file stays memory-mapped. Lookup compares UTF-8 bytes in place and
/// creates `String` values only for candidates returned to the suggestion engine.
final class ConversationalHebrewModel: @unchecked Sendable {
    private static let resourceName = "ConversationalHebrew"
    private static let resourceExtension = "akn1"
    private static let triPairsU32Flag: UInt16 = 1
    private static let sectionCount = 11
    private static let headerSize = 32 + sectionCount * 8

    private enum Section: Int, CaseIterable {
        case strings
        case words
        case counts
        case alpha
        case lengthFirst
        case byLength
        case biFirst
        case biFollow
        case triPairs
        case triFirst
        case triFollow
    }

    private struct Span {
        let offset: Int
        let length: Int
    }

    private struct Header {
        let flags: UInt16
        let vocabularyCount: Int
        let bigramRowCount: Int
        let bigramEdgeCount: Int
        let trigramKeyCount: Int
        let trigramEdgeCount: Int
        let sections: [Span]
    }

    private final class Mapping {
        let pointer: UnsafeRawPointer
        let count: Int

        init?(url: URL) {
            let descriptor = open(url.path, O_RDONLY)
            guard descriptor >= 0 else { return nil }
            defer { close(descriptor) }

            var status = stat()
            guard fstat(descriptor, &status) == 0, status.st_size > 0,
                status.st_size <= off_t(Int.max)
            else { return nil }

            count = Int(status.st_size)
            let mapped = mmap(nil, count, PROT_READ, MAP_PRIVATE, descriptor, 0)
            guard mapped != MAP_FAILED, let mapped else { return nil }
            pointer = UnsafeRawPointer(mapped)
        }

        deinit {
            munmap(UnsafeMutableRawPointer(mutating: pointer), count)
        }
    }

    private enum Cache {
        case unloaded
        case loaded(ConversationalHebrewModel?)
    }

    private static let cache = OSAllocatedUnfairLock(initialState: Cache.unloaded)
    private static let logger = Logger(
        subsystem: "com.nitai.aikeyboard", category: "ConversationalHebrewModel")

    private let mapping: Mapping
    private let header: Header

    private init?(url: URL) {
        guard let mapping = Mapping(url: url),
            let header = Self.readHeader(from: mapping)
        else { return nil }
        self.mapping = mapping
        self.header = header
        guard validate() else { return nil }
    }

    static func rank(of word: String) -> Int? {
        cached()?.rank(of: word)
    }

    static func knows(_ word: String) -> Bool {
        rank(of: word) != nil
    }

    static func words(startingWith prefix: String, limit: Int) -> [String] {
        cached()?.words(startingWith: prefix, limit: limit) ?? []
    }

    static func followers(after words: [String], limit: Int) -> [String] {
        cached()?.followers(after: words, limit: limit) ?? []
    }

    static func warm() {
        _ = cached()
    }

    static func purge() {
        cache.withLock { $0 = .unloaded }
    }

    static func load(at url: URL) -> ConversationalHebrewModel? {
        ConversationalHebrewModel(url: url)
    }

    static func bundledResourceURL() -> URL? {
        #if HARNESS
        if ProcessInfo.processInfo.environment["DISABLE_CONVERSATIONAL_HEBREW"] == "1" {
            return nil
        }
        guard
            let path = ProcessInfo.processInfo.environment["CONVERSATIONAL_HEBREW_MODEL"],
            !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
        #else
        return Bundle.module.url(forResource: resourceName, withExtension: resourceExtension)
        #endif
    }

    func rank(of word: String) -> Int? {
        identifier(of: Array(SeedLanguageModel.fold(word).utf8))
    }

    func knows(_ word: String) -> Bool {
        rank(of: word) != nil
    }

    func words(startingWith prefix: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let folded = Array(SeedLanguageModel.fold(prefix).utf8)
        guard !folded.isEmpty else { return [] }

        var low = lowerBound(of: folded)
        var best: [Int] = []
        while low < header.vocabularyCount {
            guard let identifier = u32(.alpha, low) else { return [] }
            let wordID = Int(identifier)
            guard wordHasPrefix(wordID, folded) else { break }
            if compareWord(wordID, to: folded) != 0 {
                insertByRank(wordID, into: &best, limit: limit)
            }
            low += 1
        }
        return best.compactMap(word)
    }

    func followers(after words: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let tail = words.suffix(2)
        guard let lastWord = tail.last,
            let last = identifier(of: Array(SeedLanguageModel.fold(lastWord).utf8))
        else { return [] }

        var seen = Set<Int>()
        var out: [Int] = []
        if tail.count == 2, let firstWord = tail.first,
            let first = identifier(of: Array(SeedLanguageModel.fold(firstWord).utf8))
        {
            appendTrigramFollowers(
                first: first, second: last, limit: limit,
                seen: &seen, out: &out)
        }
        if out.count < limit {
            appendBigramFollowers(
                word: last, limit: limit, seen: &seen, out: &out)
        }
        return out.compactMap(word)
    }

    private static func cached() -> ConversationalHebrewModel? {
        cache.withLock { state in
            switch state {
            case .loaded(let model):
                return model
            case .unloaded:
                guard let url = bundledResourceURL() else {
                    state = .loaded(nil)
                    return nil
                }
                let model = ConversationalHebrewModel(url: url)
                if model == nil {
                    #if !HARNESS
                    logger.error("ConversationalHebrew.akn1 is missing or invalid")
                    #endif
                }
                state = .loaded(model)
                return model
            }
        }
    }

    private static func readHeader(from mapping: Mapping) -> Header? {
        guard mapping.count >= headerSize else { return nil }
        let bytes = UnsafeRawBufferPointer(start: mapping.pointer, count: mapping.count)
        guard bytes[0] == 0x41, bytes[1] == 0x4B, bytes[2] == 0x4E, bytes[3] == 0x31,
            readU16(mapping.pointer, at: 4) == 1,
            bytes[8] == 0x68, bytes[9] == 0x65, bytes[10] == 0, bytes[11] == 0
        else { return nil }

        let flags = readU16(mapping.pointer, at: 6)
        guard flags & ~triPairsU32Flag == 0 else { return nil }
        let counts = (0..<5).map { Int(readU32(mapping.pointer, at: 12 + $0 * 4)) }

        var sections: [Span] = []
        sections.reserveCapacity(sectionCount)
        for index in 0..<sectionCount {
            let offset = Int(readU32(mapping.pointer, at: 32 + index * 8))
            let length = Int(readU32(mapping.pointer, at: 36 + index * 8))
            guard offset >= headerSize, offset % 4 == 0,
                offset <= mapping.count, length <= mapping.count - offset
            else { return nil }
            sections.append(Span(offset: offset, length: length))
        }
        for pair in zip(sections, sections.dropFirst()) {
            let paddedLength = pair.0.length + ((-pair.0.length) & 3)
            guard pair.0.offset <= pair.1.offset,
                paddedLength <= pair.1.offset - pair.0.offset
            else { return nil }
        }

        return Header(
            flags: flags,
            vocabularyCount: counts[0],
            bigramRowCount: counts[1],
            bigramEdgeCount: counts[2],
            trigramKeyCount: counts[3],
            trigramEdgeCount: counts[4],
            sections: sections)
    }

    private func validate() -> Bool {
        let vocab = header.vocabularyCount
        guard vocab > 0, vocab <= Int(UInt16.max),
            exactLength(.words, vocab, width: 6),
            exactLength(.counts, vocab, width: 4),
            exactLength(.alpha, vocab, width: 4),
            exactLength(.byLength, vocab, width: 4),
            exactLength(.biFirst, vocab + 1, width: 4),
            exactLength(.biFollow, header.bigramEdgeCount, width: 4),
            exactLength(
                .triPairs, header.trigramKeyCount,
                width: header.flags & Self.triPairsU32Flag != 0 ? 4 : 8),
            exactLength(.triFirst, header.trigramKeyCount + 1, width: 4),
            exactLength(.triFollow, header.trigramEdgeCount, width: 4),
            span(.lengthFirst).length >= 8,
            span(.lengthFirst).length % 4 == 0
        else { return false }

        var previousCount = UInt32.max
        var previousWord: Int?
        for wordID in 0..<vocab {
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

        guard validatePermutation(.alpha), validatePermutation(.byLength) else { return false }
        for index in 1..<vocab {
            guard let left = u32(.alpha, index - 1), let right = u32(.alpha, index),
                compareWords(Int(left), Int(right)) == .orderedAscending
            else { return false }
        }

        let lengthEntries = span(.lengthFirst).length / 4
        var previous = 0
        for bucket in 0..<lengthEntries {
            guard let raw = u32(.lengthFirst, bucket) else { return false }
            let next = Int(raw)
            guard next >= previous, next <= vocab else { return false }
            if bucket > 0 {
                for index in previous..<next {
                    guard let wordID = u32(.byLength, index),
                        wordDescriptor(Int(wordID))?.characterCount == bucket - 1
                    else { return false }
                }
            }
            previous = next
        }
        guard previous == vocab else { return false }

        var bigramRows = 0
        guard
            validateCSR(
                first: .biFirst, followers: .biFollow, rows: vocab,
                edgeCount: header.bigramEdgeCount, nonemptyRows: &bigramRows),
            bigramRows == header.bigramRowCount
        else { return false }

        var priorPair: UInt64?
        for index in 0..<header.trigramKeyCount {
            guard let pair = trigramPair(at: index) else { return false }
            let first = Int(pair >> 32)
            let second = Int(pair & 0xFFFF_FFFF)
            guard first < vocab, second < vocab, priorPair.map({ $0 < pair }) ?? true
            else { return false }
            priorPair = pair
        }
        var ignoredRows = 0
        return validateCSR(
            first: .triFirst, followers: .triFollow, rows: header.trigramKeyCount,
            edgeCount: header.trigramEdgeCount, nonemptyRows: &ignoredRows)
    }

    private func validateCSR(
        first: Section, followers: Section, rows: Int, edgeCount: Int,
        nonemptyRows: inout Int
    ) -> Bool {
        var previous = 0
        for row in 0...rows {
            guard let raw = u32(first, row) else { return false }
            let next = Int(raw)
            guard next >= previous, next <= edgeCount else { return false }
            if row > 0, next > previous { nonemptyRows += 1 }
            previous = next
        }
        guard previous == edgeCount else { return false }
        for index in 0..<edgeCount {
            guard let follower = u32(followers, index),
                follower < UInt32(header.vocabularyCount)
            else { return false }
        }
        return true
    }

    private func validatePermutation(_ section: Section) -> Bool {
        var seen = [Bool](repeating: false, count: header.vocabularyCount)
        for index in 0..<header.vocabularyCount {
            guard let value = u32(section, index), value < UInt32(seen.count),
                !seen[Int(value)]
            else { return false }
            seen[Int(value)] = true
        }
        return true
    }

    private func validUTF8(_ wordID: Int, expectedCharacters: Int) -> Bool {
        guard let bytes = wordBytes(wordID) else { return false }
        var index = 0
        var characters = 0
        while index < bytes.count {
            let first = bytes[index]
            let width: Int
            let minimum: UInt32
            var scalar: UInt32
            switch first {
            case 0x00...0x7F:
                width = 1
                minimum = 0
                scalar = UInt32(first)
            case 0xC2...0xDF:
                width = 2
                minimum = 0x80
                scalar = UInt32(first & 0x1F)
            case 0xE0...0xEF:
                width = 3
                minimum = 0x800
                scalar = UInt32(first & 0x0F)
            case 0xF0...0xF4:
                width = 4
                minimum = 0x10000
                scalar = UInt32(first & 0x07)
            default:
                return false
            }
            guard width <= bytes.count - index else { return false }
            for offset in 1..<width {
                let continuation = bytes[index + offset]
                guard continuation & 0xC0 == 0x80 else { return false }
                scalar = (scalar << 6) | UInt32(continuation & 0x3F)
            }
            guard scalar >= minimum, scalar <= 0x10FFFF,
                !(0xD800...0xDFFF).contains(scalar)
            else { return false }
            index += width
            characters += 1
        }
        return characters == expectedCharacters
    }

    private func identifier(of bytes: [UInt8]) -> Int? {
        guard !bytes.isEmpty else { return nil }
        let index = lowerBound(of: bytes)
        guard index < header.vocabularyCount, let raw = u32(.alpha, index) else { return nil }
        let wordID = Int(raw)
        return compareWord(wordID, to: bytes) == 0 ? wordID : nil
    }

    private func lowerBound(of bytes: [UInt8]) -> Int {
        var low = 0
        var high = header.vocabularyCount
        while low < high {
            let middle = (low + high) / 2
            guard let raw = u32(.alpha, middle) else { return high }
            if compareWord(Int(raw), to: bytes) < 0 {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func appendBigramFollowers(
        word: Int, limit: Int, seen: inout Set<Int>, out: inout [Int]
    ) {
        guard let start = u32(.biFirst, word), let end = u32(.biFirst, word + 1) else { return }
        appendFollowers(
            section: .biFollow, range: Int(start)..<Int(end), limit: limit,
            seen: &seen, out: &out)
    }

    private func appendTrigramFollowers(
        first: Int, second: Int, limit: Int, seen: inout Set<Int>, out: inout [Int]
    ) {
        let key = (UInt64(first) << 32) | UInt64(second)
        var low = 0
        var high = header.trigramKeyCount
        while low < high {
            let middle = (low + high) / 2
            guard let value = trigramPair(at: middle) else { return }
            if value < key {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < header.trigramKeyCount, trigramPair(at: low) == key,
            let start = u32(.triFirst, low), let end = u32(.triFirst, low + 1)
        else { return }
        appendFollowers(
            section: .triFollow, range: Int(start)..<Int(end), limit: limit,
            seen: &seen, out: &out)
    }

    private func appendFollowers(
        section: Section, range: Range<Int>, limit: Int,
        seen: inout Set<Int>, out: inout [Int]
    ) {
        for index in range {
            guard let raw = u32(section, index) else { return }
            let wordID = Int(raw)
            guard seen.insert(wordID).inserted else { continue }
            out.append(wordID)
            if out.count == limit { return }
        }
    }

    private func insertByRank(_ wordID: Int, into best: inout [Int], limit: Int) {
        let insertion = best.firstIndex(where: { wordID < $0 }) ?? best.endIndex
        best.insert(wordID, at: insertion)
        if best.count > limit { best.removeLast() }
    }

    private func word(_ wordID: Int) -> String? {
        guard let bytes = wordBytes(wordID) else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func wordHasPrefix(_ wordID: Int, _ prefix: [UInt8]) -> Bool {
        guard let bytes = wordBytes(wordID), bytes.count >= prefix.count else { return false }
        return bytes.prefix(prefix.count).elementsEqual(prefix)
    }

    private func compareWord(_ wordID: Int, to bytes: [UInt8]) -> Int {
        guard let word = wordBytes(wordID) else { return 1 }
        for (left, right) in zip(word, bytes) {
            if left != right { return left < right ? -1 : 1 }
        }
        if word.count == bytes.count { return 0 }
        return word.count < bytes.count ? -1 : 1
    }

    private func compareWords(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        guard let left = wordBytes(lhs), let right = wordBytes(rhs) else { return .orderedSame }
        for (a, b) in zip(left, right) {
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        if left.count == right.count { return .orderedSame }
        return left.count < right.count ? .orderedAscending : .orderedDescending
    }

    private func wordBytes(_ wordID: Int) -> UnsafeRawBufferPointer? {
        guard let descriptor = wordDescriptor(wordID) else { return nil }
        let strings = span(.strings)
        guard descriptor.offset <= strings.length,
            descriptor.byteCount <= strings.length - descriptor.offset
        else { return nil }
        return UnsafeRawBufferPointer(
            start: mapping.pointer.advanced(by: strings.offset + descriptor.offset),
            count: descriptor.byteCount)
    }

    private func wordDescriptor(
        _ wordID: Int
    ) -> (offset: Int, characterCount: Int, byteCount: Int)? {
        guard wordID >= 0, wordID < header.vocabularyCount else { return nil }
        let words = span(.words)
        let local = wordID * 6
        guard local <= words.length, 6 <= words.length - local else { return nil }
        let pointer = mapping.pointer.advanced(by: words.offset + local)
        return (
            Int(Self.readU32(pointer, at: 0)),
            Int(pointer.load(fromByteOffset: 4, as: UInt8.self)),
            Int(pointer.load(fromByteOffset: 5, as: UInt8.self))
        )
    }

    private func trigramPair(at index: Int) -> UInt64? {
        guard index >= 0, index < header.trigramKeyCount else { return nil }
        if header.flags & Self.triPairsU32Flag != 0 {
            guard let packed = u32(.triPairs, index) else { return nil }
            return (UInt64(packed >> 16) << 32) | UInt64(packed & 0xFFFF)
        }
        let section = span(.triPairs)
        let local = index * 8
        guard local <= section.length, 8 <= section.length - local else { return nil }
        return UInt64(
            littleEndian: mapping.pointer.loadUnaligned(
                fromByteOffset: section.offset + local, as: UInt64.self))
    }

    private func u32(_ section: Section, _ index: Int) -> UInt32? {
        guard index >= 0 else { return nil }
        let section = span(section)
        let local = index * 4
        guard local <= section.length, 4 <= section.length - local else { return nil }
        return Self.readU32(mapping.pointer, at: section.offset + local)
    }

    private func exactLength(_ section: Section, _ count: Int, width: Int) -> Bool {
        count <= Int.max / width && span(section).length == count * width
    }

    private func span(_ section: Section) -> Span {
        header.sections[section.rawValue]
    }

    private static func readU16(_ pointer: UnsafeRawPointer, at offset: Int) -> UInt16 {
        UInt16(
            littleEndian: pointer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }

    private static func readU32(_ pointer: UnsafeRawPointer, at offset: Int) -> UInt32 {
        UInt32(
            littleEndian: pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}
