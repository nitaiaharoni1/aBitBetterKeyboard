#!/usr/bin/env python3
"""Generate and verify the shipped AKN1 Hebrew predictor.

Derived from the measured prototype's hebtext.py, build_clean.py,
clean_tables.py, and pack.py. Only the two pinned Leipzig news corpora enter
the counts. NumPy is a generation-time dependency and is not used by the app.
"""

import argparse
import collections
import hashlib
import mmap
import pathlib
import re
import struct
import tarfile
import unicodedata
import urllib.request

MAGIC = b"AKN1"
VERSION = 1
TRI_PAIRS_U32 = 1
VOCAB_LIMIT = 20_000
MIN_UNIGRAM = 2
MIN_BIGRAM = 5
MIN_TRIGRAM = 5
MAX_FOLLOWERS = 8
SECTIONS = (
    "strings",
    "words",
    "counts",
    "alpha",
    "length_first",
    "by_length",
    "bi_first",
    "bi_follow",
    "tri_pairs",
    "tri_first",
    "tri_follow",
)
EXPECTED_SIZE = 2_516_844
EXPECTED_SHA256 = "5a6f47557e891d113b50bf3ad41b0572ca49618b9e3554e184c2687818a7a6cc"

INPUTS = (
    (
        "heb_news_2020_1M",
        "https://downloads.wortschatz-leipzig.de/corpora/heb_news_2020_1M.tar.gz",
        "e81bb0b4f2f13bc343da8b732768582075257634600c359e55283774690b3213",
    ),
    (
        "heb_newscrawl_2011_1M",
        "https://downloads.wortschatz-leipzig.de/corpora/heb_newscrawl_2011_1M.tar.gz",
        "ad78abb765890d4055bd5105b6ae0471c45c76ad0b0fcb54b55a4d8e193bac7b",
    ),
)

BIDI = {
    0x200E,
    0x200F,
    0x202A,
    0x202B,
    0x202C,
    0x202D,
    0x202E,
    0x2066,
    0x2067,
    0x2068,
    0x2069,
    0x061C,
    0xFEFF,
}
NIQQUD = re.compile(r"[\u0591-\u05BD\u05BF\u05C1\u05C2\u05C4\u05C5\u05C7]")
IN_WORD_MARKS = re.compile(r"[:\u00B0\u00BA\u02C6\u005E\u2191\u2193\u0060\u00B4\u2018\uF000-\uF8FF]")
TOKEN_OK = re.compile(r"^[\u05D0-\u05EA]+(?:['\"\-][\u05D0-\u05EA]+)*$")
STRUCTURAL = re.compile(r"[<>()\[\]{}@*+/\\|~0-9A-Za-z]")
EDGE = ".,;?!=\u05C3\u2026\"'-"
REPLACEMENTS = {"\u05F3": "'", "\u05F4": '"', "\u2019": "'", "\u05BE": "-"}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fold(text):
    text = "".join(character for character in text if ord(character) not in BIDI)
    text = NIQQUD.sub("", unicodedata.normalize("NFC", text))
    for source, replacement in REPLACEMENTS.items():
        text = text.replace(source, replacement)
    return text.lower()


def token_runs(text):
    runs = []
    current = []
    for word in fold(text).split():
        if STRUCTURAL.search(word):
            if current:
                runs.append(current)
                current = []
            continue
        stripped = IN_WORD_MARKS.sub("", word).strip(EDGE)
        if stripped and TOKEN_OK.fullmatch(stripped):
            current.append(stripped)
        elif current:
            runs.append(current)
            current = []
    if current:
        runs.append(current)
    return runs


def fetch_inputs(cache):
    cache.mkdir(parents=True, exist_ok=True)
    for name, url, expected in INPUTS:
        path = cache / f"{name}.tar.gz"
        if not path.exists():
            print(f"downloading {url}", flush=True)
            request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(request) as response, path.open("wb") as output:
                while chunk := response.read(1 << 20):
                    output.write(chunk)
        actual = sha256(path)
        if actual != expected:
            raise SystemExit(f"{path}: SHA-256 {actual}, expected {expected}")
        print(f"verified {path.name}", flush=True)


def sentences(archive):
    with tarfile.open(archive, "r:gz") as source:
        member = next(name for name in source.getnames() if name.endswith("-sentences.txt"))
        with source.extractfile(member) as handle:
            for raw in handle:
                _, _, text = raw.decode("utf-8", "replace").partition("\t")
                if text:
                    yield text.rstrip("\n")


def encode(cache):
    import numpy as np

    identifiers = {}
    stream = []
    source_tokens = {}
    for name, _, _ in INPUTS:
        before = len(stream)
        for sentence in sentences(cache / f"{name}.tar.gz"):
            for run in token_runs(sentence):
                for word in run:
                    identifier = identifiers.get(word)
                    if identifier is None:
                        identifier = identifiers[word] = len(identifiers)
                    stream.append(identifier)
                stream.append(-1)
        source_tokens[name] = len(stream) - before
        print(f"{name}: vocabulary={len(identifiers):,}", flush=True)
    vocabulary = [None] * len(identifiers)
    for word, identifier in identifiers.items():
        vocabulary[identifier] = word
    return np.asarray(stream, dtype=np.int64), vocabulary, source_tokens


def ngrams(stream, order, vocabulary_size):
    import numpy as np

    columns = [stream[index : len(stream) - (order - 1 - index)] for index in range(order)]
    accepted = columns[0] >= 0
    for column in columns[1:]:
        accepted &= column >= 0
    keys = np.zeros(int(accepted.sum()), dtype=np.int64)
    for column in columns:
        keys *= vocabulary_size
        keys += column[accepted]
    return np.unique(keys, return_counts=True)


def decode_key(key, order, vocabulary_size):
    parts = []
    for _ in range(order):
        parts.append(int(key % vocabulary_size))
        key //= vocabulary_size
    return tuple(reversed(parts))


def build_tables(cache):
    import numpy as np

    stream, vocabulary, _ = encode(cache)
    size = len(vocabulary)
    keys, counts = ngrams(stream, 1, size)
    order = np.argsort(-counts, kind="stable")
    unigram_ids = keys[order]
    unigram_counts = counts[order]
    keep = [
        (int(identifier), int(count))
        for identifier, count in zip(unigram_ids, unigram_counts)
        if count >= MIN_UNIGRAM
    ][:VOCAB_LIMIT]
    selected = {identifier for identifier, _ in keep}
    selected_words = [(vocabulary[identifier], count) for identifier, count in keep]

    edges = {}
    for width, floor in ((2, MIN_BIGRAM), (3, MIN_TRIGRAM)):
        keys, counts = ngrams(stream, width, size)
        rows = []
        for key, count in zip(keys.tolist(), counts.tolist()):
            if count < floor:
                continue
            identifiers = decode_key(key, width, size)
            if all(identifier in selected for identifier in identifiers):
                rows.append((tuple(vocabulary[identifier] for identifier in identifiers), int(count)))
        edges[width] = rows
        print(f"{width}-grams retained before follower cap: {len(rows):,}", flush=True)
    return selected_words, edges[2], edges[3]


def pack(unigrams, bigrams, trigrams, output):
    ranked = sorted(unigrams, key=lambda item: (-item[1], item[0]))
    identifiers = {word: index for index, (word, _) in enumerate(ranked)}

    bigram_table = collections.defaultdict(list)
    for (first, follower), count in bigrams:
        bigram_table[identifiers[first]].append((identifiers[follower], count))
    trigram_table = collections.defaultdict(list)
    for (first, second, follower), count in trigrams:
        trigram_table[(identifiers[first], identifiers[second])].append(
            (identifiers[follower], count)
        )
    for table in (bigram_table, trigram_table):
        for key in table:
            table[key] = sorted(table[key], key=lambda item: (-item[1], item[0]))[
                :MAX_FOLLOWERS
            ]

    strings = bytearray()
    words = bytearray()
    counts = bytearray()
    for word, count in ranked:
        encoded = word.encode("utf-8")
        words += struct.pack("<IBB", len(strings), len(word), len(encoded))
        strings += encoded
        counts += struct.pack("<I", min(count, 0xFFFFFFFF))

    alpha = b"".join(
        struct.pack("<I", identifiers[word]) for word, _ in sorted(ranked)
    )
    buckets = collections.defaultdict(list)
    for word, _ in ranked:
        buckets[len(word)].append(identifiers[word])
    longest = max(buckets)
    by_length = bytearray()
    length_first = bytearray()
    for length in range(longest + 2):
        length_first += struct.pack("<I", len(by_length) // 4)
        by_length += b"".join(struct.pack("<I", value) for value in buckets.get(length, []))

    bi_first = bytearray()
    bi_follow = bytearray()
    for word_id in range(len(ranked)):
        bi_first += struct.pack("<I", len(bi_follow) // 4)
        bi_follow += b"".join(
            struct.pack("<I", follower) for follower, _ in bigram_table.get(word_id, [])
        )
    bi_first += struct.pack("<I", len(bi_follow) // 4)

    tri_pairs = bytearray()
    tri_first = bytearray()
    tri_follow = bytearray()
    for first, second in sorted(trigram_table):
        tri_pairs += struct.pack("<I", (first << 16) | second)
        tri_first += struct.pack("<I", len(tri_follow) // 4)
        tri_follow += b"".join(
            struct.pack("<I", follower)
            for follower, _ in trigram_table[(first, second)]
        )
    tri_first += struct.pack("<I", len(tri_follow) // 4)

    payload = {
        "strings": bytes(strings),
        "words": bytes(words),
        "counts": bytes(counts),
        "alpha": alpha,
        "length_first": bytes(length_first),
        "by_length": bytes(by_length),
        "bi_first": bytes(bi_first),
        "bi_follow": bytes(bi_follow),
        "tri_pairs": bytes(tri_pairs),
        "tri_first": bytes(tri_first),
        "tri_follow": bytes(tri_follow),
    }
    header_size = 32 + len(SECTIONS) * 8
    body = bytearray()
    section_table = []
    for name in SECTIONS:
        section = payload[name]
        section_table.append((header_size + len(body), len(section)))
        body += section
        body += b"\0" * ((-len(section)) % 4)

    header = bytearray(MAGIC)
    header += struct.pack("<HH", VERSION, TRI_PAIRS_U32)
    header += b"he\0\0"
    header += struct.pack(
        "<IIIII",
        len(ranked),
        len(bigram_table),
        len(bi_follow) // 4,
        len(trigram_table),
        len(tri_follow) // 4,
    )
    for offset, length in section_table:
        header += struct.pack("<II", offset, length)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(header + body)
    return ranked, bigram_table, trigram_table


class Reader:
    def __init__(self, path):
        self.handle = path.open("rb")
        self.data = mmap.mmap(self.handle.fileno(), 0, access=mmap.ACCESS_READ)
        if len(self.data) < 120:
            raise ValueError("truncated header")
        self.version, self.flags = struct.unpack_from("<HH", self.data, 4)
        self.language = self.data[8:12].rstrip(b"\0").decode()
        (
            self.vocabulary_count,
            self.bigram_rows,
            self.bigram_edges,
            self.trigram_keys,
            self.trigram_edges,
        ) = struct.unpack_from("<IIIII", self.data, 12)
        self.sections = {
            name: struct.unpack_from("<II", self.data, 32 + index * 8)
            for index, name in enumerate(SECTIONS)
        }

    def close(self):
        self.data.close()
        self.handle.close()

    def u32(self, section, index):
        offset, length = self.sections[section]
        if index < 0 or index * 4 + 4 > length:
            raise ValueError(f"{section}[{index}] out of bounds")
        return struct.unpack_from("<I", self.data, offset + index * 4)[0]

    def word(self, word_id):
        offset, length = self.sections["words"]
        if word_id < 0 or word_id * 6 + 6 > length:
            raise ValueError(f"word {word_id} out of bounds")
        start, characters, byte_count = struct.unpack_from(
            "<IBB", self.data, offset + word_id * 6
        )
        strings, string_length = self.sections["strings"]
        if start + byte_count > string_length:
            raise ValueError(f"word {word_id} string out of bounds")
        word = self.data[strings + start : strings + start + byte_count].decode("utf-8")
        if len(word) != characters:
            raise ValueError(f"word {word_id} character count mismatch")
        return word

    def identifier(self, word):
        low, high = 0, self.vocabulary_count
        while low < high:
            middle = (low + high) // 2
            if self.word(self.u32("alpha", middle)) < word:
                low = middle + 1
            else:
                high = middle
        if low < self.vocabulary_count:
            word_id = self.u32("alpha", low)
            if self.word(word_id) == word:
                return word_id
        return None

    def completions(self, prefix, limit):
        low, high = 0, self.vocabulary_count
        while low < high:
            middle = (low + high) // 2
            if self.word(self.u32("alpha", middle)) < prefix:
                low = middle + 1
            else:
                high = middle
        identifiers = []
        while low < self.vocabulary_count:
            word_id = self.u32("alpha", low)
            word = self.word(word_id)
            if not word.startswith(prefix):
                break
            if word != prefix:
                identifiers.append(word_id)
            low += 1
        return [self.word(word_id) for word_id in sorted(identifiers)[:limit]]

    def bigram_followers(self, word):
        word_id = self.identifier(word)
        if word_id is None:
            return []
        start = self.u32("bi_first", word_id)
        end = self.u32("bi_first", word_id + 1)
        return [self.word(self.u32("bi_follow", index)) for index in range(start, end)]

    def trigram_followers(self, first, second):
        first_id, second_id = self.identifier(first), self.identifier(second)
        if first_id is None or second_id is None:
            return []
        key = (first_id << 16) | second_id
        low, high = 0, self.trigram_keys
        while low < high:
            middle = (low + high) // 2
            offset, _ = self.sections["tri_pairs"]
            value = struct.unpack_from("<I", self.data, offset + middle * 4)[0]
            if value < key:
                low = middle + 1
            else:
                high = middle
        if low >= self.trigram_keys:
            return []
        offset, _ = self.sections["tri_pairs"]
        if struct.unpack_from("<I", self.data, offset + low * 4)[0] != key:
            return []
        start = self.u32("tri_first", low)
        end = self.u32("tri_first", low + 1)
        return [self.word(self.u32("tri_follow", index)) for index in range(start, end)]


def verify_binary(path, expected=None):
    reader = Reader(path)
    checks = []

    def check(name, condition):
        checks.append((name, bool(condition)))

    check("magic", reader.data[:4] == MAGIC)
    check("version and language", (reader.version, reader.language) == (VERSION, "he"))
    check("u32 trigram-pair flag", reader.flags == TRI_PAIRS_U32)
    check("file size", path.stat().st_size == EXPECTED_SIZE)
    check("file SHA-256", sha256(path) == EXPECTED_SHA256)
    check("vocabulary count", reader.vocabulary_count == VOCAB_LIMIT)
    check(
        "edge counts",
        (
            reader.bigram_rows,
            reader.bigram_edges,
            reader.trigram_keys,
            reader.trigram_edges,
        )
        == (19_700, 122_400, 92_259, 159_454),
    )
    check(
        "section bounds",
        all(
            offset >= 120 and offset % 4 == 0 and length <= len(reader.data) - offset
            for offset, length in reader.sections.values()
        ),
    )
    words = [reader.word(index) for index in range(reader.vocabulary_count)]
    check("ranked words unique", len(set(words)) == reader.vocabulary_count)
    alpha = [reader.u32("alpha", index) for index in range(reader.vocabulary_count)]
    check(
        "alpha index round-trip",
        sorted(alpha) == list(range(reader.vocabulary_count))
        and [words[index] for index in alpha] == sorted(words),
    )
    check("rank lookup", all(reader.identifier(words[index]) == index for index in range(0, 20_000, 97)))
    check("prefix completion", reader.completions("תוד", 3) == ["תודה", "תודעה"])
    check("one-word followers", reader.bigram_followers("אני")[:6] == ["לא", "חושב", "רוצה", "מקווה", "יודע", "רואה"])
    check("two-word followers present", bool(reader.trigram_followers("אני", "לא")))

    if expected is not None:
        ranked, bigrams, trigrams = expected
        check("rank-zero round-trip", reader.word(0) == ranked[0][0])
        sampled_bigrams = list(bigrams.items())[:: max(1, len(bigrams) // 400)]
        check(
            "bigram round-trip",
            all(
                reader.bigram_followers(ranked[first][0])
                == [ranked[follower][0] for follower, _ in followers]
                for first, followers in sampled_bigrams
            ),
        )
        sampled_trigrams = list(trigrams.items())[:: max(1, len(trigrams) // 1000)]
        check(
            "trigram round-trip",
            all(
                reader.trigram_followers(ranked[first][0], ranked[second][0])
                == [ranked[follower][0] for follower, _ in followers]
                for (first, second), followers in sampled_trigrams
            ),
        )

    failed = [name for name, passed in checks if not passed]
    reader.close()
    if failed:
        raise SystemExit("binary verification failed: " + ", ".join(failed))
    print(f"{len(checks)}/{len(checks)} binary checks passed on {path.name}")


def verify_provenance(path, cache):
    reader = Reader(path)
    packed = {reader.word(index) for index in range(reader.vocabulary_count)}
    reader.close()
    observed = set()
    attribution = collections.Counter()
    per_source = {}
    for name, _, _ in INPUTS:
        source_words = set()
        for sentence in sentences(cache / f"{name}.tar.gz"):
            for run in token_runs(sentence):
                source_words.update(run)
        per_source[name] = source_words
        observed.update(source_words)
        print(f"scanned {name}: {len(source_words):,} forms", flush=True)
    missing = packed - observed
    for word in packed:
        sources = tuple(name for name, _, _ in INPUTS if word in per_source[name])
        attribution[sources] += 1
    if missing:
        raise SystemExit(f"{len(missing)} packed forms were not observed: {sorted(missing)[:20]}")
    print("provenance passed: 20,000/20,000 forms observed in accepted sources")
    for sources, count in attribution.most_common():
        print(f"  {','.join(sources)}: {count:,}")


def parse_args():
    root = pathlib.Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--cache-dir",
        type=pathlib.Path,
        default=pathlib.Path.home() / ".cache/ai-keyboard/hebrew-corpora",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=root
        / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/ConversationalHebrew.akn1",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="verify the existing binary and source provenance without regenerating",
    )
    return parser.parse_args()


def main():
    arguments = parse_args()
    fetch_inputs(arguments.cache_dir)
    if arguments.verify_only:
        verify_binary(arguments.output)
        verify_provenance(arguments.output, arguments.cache_dir)
        return
    tables = build_tables(arguments.cache_dir)
    expected = pack(*tables, arguments.output)
    verify_binary(arguments.output, expected)
    verify_provenance(arguments.output, arguments.cache_dir)


if __name__ == "__main__":
    main()
