"""The decoder: key sequence in, ranked words out.

Deliberately the *weak* decoder — a frequency-ranked lexicon and nothing else,
with an optional bigram pass. It is a floor, not a model of the shipping engine,
which also has `UITextChecker`, the personal model that outranks everything, the
learned word list and the code-switch list. Read a number here as "at least this
good", never as a prediction.
"""

from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path

from grouping import clitic_forms, normalise, word_core


class Lexicon:
    """Words and their frequencies, most common first."""

    def __init__(self, language: str, entries: list[tuple[str, float]], source: str):
        self.language = language
        self.source = source
        self.freq: dict[str, float] = {}
        for word, frequency in entries:
            clean = word_core(normalise(word))
            if not clean:
                continue
            # Two spellings can fold together; keep the commoner reading.
            if frequency > self.freq.get(clean, 0.0):
                self.freq[clean] = frequency

    @classmethod
    def load(cls, path) -> "Lexicon":
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        return cls(
            payload["language"],
            [(w, f) for w, f in payload["words"]],
            payload.get("source", str(path)),
        )

    @classmethod
    def from_ranked_lines(cls, language: str, path, source: str | None = None) -> "Lexicon":
        """One word per line, commonest first — the form the keyboard ships."""
        words = Path(path).read_text(encoding="utf-8").splitlines()
        ranked = [(word, 1.0 / (index + 1)) for index, word in enumerate(words) if word]
        return cls(language, ranked, source or str(path))

    def __len__(self) -> int:
        return len(self.freq)

    def with_clitic_forms(self, penalty: float = 0.1) -> "Lexicon":
        """Every stem also reachable through its glued readings.

        This is what `HebrewMorphology.splits` buys the real engine: one entry
        for `עבודה` serves `לעבודה`, `בעבודה` and `מהעבודה`, none of which any
        dictionary lists. The penalty keeps a glued reading below the bare word
        it was built from, matching the half-tier `SuggestionEngine.score`
        charges per clitic stripped.

        **A synthesised form may never overwrite a word the corpus measured.**
        Without that rule this clobbered 28.9% of the Hebrew lexicon: `ללא`
        ("without") had its real frequency replaced by a 3.1× larger figure
        derived from `לא` ("not"), and `בעל` ("husband") by a 3.5× one derived
        from `על` ("on"). Those are different words, and even where the glued
        form *is* the derivation — `ולא`, `שזה`, `ואני` are all in the list
        already — a measured count beats an invented one. The synthetic
        frequency exists to reach forms no corpus recorded, and nothing else.
        """
        grown = dict(self.freq)
        for stem, frequency in self.freq.items():
            for glued in clitic_forms(stem):
                if glued in self.freq:
                    continue
                if frequency * penalty > grown.get(glued, 0.0):
                    grown[glued] = frequency * penalty
        out = Lexicon.__new__(Lexicon)
        out.language = self.language
        out.source = self.source + " + clitic forms"
        out.freq = grown
        return out


class Decoder:
    """Every lexicon word this layout can type, indexed by the keys it presses."""

    def __init__(self, lexicon: Lexicon, layout):
        self.lexicon = lexicon
        self.layout = layout
        index: dict[tuple, list[str]] = defaultdict(list)
        self.untypable = 0
        for word in lexicon.freq:
            code = layout.code(word)
            if code is None:
                self.untypable += 1
                continue
            index[code].append(word)
        for code, words in index.items():
            words.sort(key=lambda w: (-lexicon.freq[w], w))
        self.index: dict[tuple, list[str]] = dict(index)

    def candidates(self, code: tuple) -> list[str]:
        return self.index.get(code, [])

    def ranked(self, code: tuple, previous: str | None, bigrams) -> list[str]:
        """Candidates for this code, best first.

        Without `bigrams` this is pure frequency order. With it, a word the
        preceding word is known to be followed by is promoted — the same claim
        `SuggestionEngine.score` makes when it adds 400 for `followsContext`,
        which is worth more than a whole source tier because "the word before it
        was `בעוד`" is stronger evidence than which dictionary a word came from.
        """
        words = self.candidates(code)
        if not bigrams or previous is None or len(words) < 2:
            return words
        following = bigrams.following(previous)
        if not following:
            return words
        return sorted(
            words,
            key=lambda w: (-following.get(w, 0), -self.lexicon.freq[w], w),
        )


class Bigrams:
    """Which word follows which, counted over the test text with the sentence
    under test held out.

    **Leave-one-out, because counting a sentence towards its own context is not
    a measurement.** It is also sparse — a few thousand sentences is nowhere near
    enough to cover a language — so the gain it shows is a floor on what real
    context is worth, not an estimate of it.
    """

    def __init__(self, sentences: list[list[str]]):
        self.total: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
        self.per_sentence: list[list[tuple[str, str]]] = []
        for words in sentences:
            pairs = list(zip(words, words[1:]))
            self.per_sentence.append(pairs)
            for left, right in pairs:
                self.total[left][right] += 1
        # Only the words appearing on the left of a pair in the held-out
        # sentence need adjusting; every other word's counts are already correct,
        # which is why `following` falls through to `total`.
        self._active: dict[str, dict[str, int]] = {}

    def hold_out(self, index: int) -> None:
        self._active = {}
        for left, right in self.per_sentence[index]:
            if left not in self._active:
                self._active[left] = dict(self.total[left])
            # Decrements once per occurrence, so a pair repeated inside one
            # sentence is fully removed rather than only once.
            self._active[left][right] -= 1

    def following(self, word: str) -> dict[str, int]:
        if word in self._active:
            return {w: c for w, c in self._active[word].items() if c > 0}
        return self.total.get(word, {})


def zipf(frequency: float) -> float:
    """wordfreq's readable scale: 1 is vanishingly rare, 7 is `the`."""
    return math.log10(frequency * 1e9) if frequency > 0 else 0.0
