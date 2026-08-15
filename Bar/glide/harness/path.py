"""The genuinely new part: turning a continuous swipe into a candidate key
sequence.

Nobody's real finger is in this file. Every path is synthesised from the
intended word's key centres plus a stated, parameterised amount of curve and
noise, so the credibility of any accuracy number in `results.json` rests
entirely on how honestly this generator's assumptions are named — each one
below is a keyword argument, swept in `run.py`, not a constant buried in the
math. **Read `Bar/glide/README.md` before quoting a number: every one there is
labelled SYNTHETIC, and this is why.**
"""

from __future__ import annotations

import math
import random

from keyboard import nearest_letter


def waypoints(word: str, centers: dict[str, tuple[float, float]]) -> list[tuple[float, float]]:
    """One point per letter that has a key, consecutive repeats collapsed.

    A swipe path does not stop and restart at a repeated letter — the finger
    is already there — so `hello` visits four distinct points (h, e, l, o),
    not five. That is also, honestly, the reason glide typing cannot tell
    `hello` from a hypothetical `helo` on geometry alone, the same collision a
    doubled letter causes for `GlideLayout.code`: see the README's collision
    count.
    """
    points: list[tuple[float, float]] = []
    for letter in word:
        if letter not in centers:
            continue
        point = centers[letter]
        if not points or points[-1] != point:
            points.append(point)
    return points


def perturb_waypoints(
    points: list[tuple[float, float]], sigma: float, rng: random.Random
) -> list[tuple[float, float]]:
    """Where the hand actually aimed for each letter, not where it should have.

    **One Gaussian draw per waypoint, not per path sample.** An earlier
    version of this generator drew fresh noise at every sample along the
    interpolated path — independent, sample to sample — which produces a
    jagged random walk no real hand motion looks like: two touch points a few
    milliseconds apart are highly correlated, not independent, so that model
    made every straight segment look like it had corners everywhere and the
    corner detector below could not separate signal from that noise at any
    threshold. Sigma is in key-width units, the same scale
    `Bar/grouped/harness/miss.py` already uses for tap noise, so the two are
    directly comparable — 0.20 there is called a fat thumb.
    """
    return [(x + rng.gauss(0, sigma), y + rng.gauss(0, sigma)) for x, y in points]


def _blend_toward_neighbour(points, index, corner_cut, look):
    """Move a waypoint a `corner_cut` fraction toward the point on its far
    side — away from the corner it forms with its neighbour on the `look`
    side. Touch-down and touch-up (index 0 and the last) are never moved:
    anchored, deliberately, the same as `reduce_to_keys` anchors them on the
    way back."""
    if corner_cut <= 0 or index == 0 or index == len(points) - 1:
        return points[index]
    neighbour_index = index + look
    if not (0 <= neighbour_index < len(points)):
        return points[index]
    px, py = points[index]
    nx, ny = points[neighbour_index]
    return (px + (nx - px) * corner_cut, py + (ny - py) * corner_cut)


def curved_path(
    points: list[tuple[float, float]], *, samples_per_segment: int, corner_cut: float,
) -> list[tuple[float, float]]:
    """Sample points along a smoothed path through (already noisy) `points`.

    `corner_cut` (0..1): how much a waypoint rounds toward a straight line
    between its own neighbours instead of being hit exactly. 0 passes through
    every key centre on the nose; 0.5 blends half the distance, which is what
    a fast real swipe does and is the mechanism by which a short middle
    letter can go missing from the sampled sequence entirely — the corner
    gets cut close enough that the path never turns there at all.

    No noise is added here; `points` already carries it, once per waypoint,
    from `perturb_waypoints`, so the interpolation between them stays smooth —
    real hand motion is continuous even when its aim is imprecise.
    """
    if not points:
        return []
    if len(points) == 1:
        return [points[0] for _ in range(samples_per_segment)]

    path: list[tuple[float, float]] = []
    n = len(points)
    for i in range(n - 1):
        a_eff = _blend_toward_neighbour(points, i, corner_cut, look=-1)
        b_eff = _blend_toward_neighbour(points, i + 1, corner_cut, look=+1)
        for s in range(samples_per_segment):
            t = s / samples_per_segment
            path.append((
                a_eff[0] + (b_eff[0] - a_eff[0]) * t,
                a_eff[1] + (b_eff[1] - a_eff[1]) * t,
            ))
    path.append(points[-1])  # touch-up: jittered by perturb_waypoints, never corner-cut
    return path


def _turning_angle(before, at, after) -> float:
    """Radians between the incoming and outgoing direction at `at`. 0 is
    dead straight, pi is a full reversal."""
    v1 = (at[0] - before[0], at[1] - before[1])
    v2 = (after[0] - at[0], after[1] - at[1])
    len1, len2 = math.hypot(*v1), math.hypot(*v2)
    if len1 < 1e-9 or len2 < 1e-9:
        return 0.0
    cos_angle = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (len1 * len2)))
    return math.acos(cos_angle)


def corner_indices(path: list[tuple[float, float]], *, angle_threshold_deg: float) -> list[int]:
    """Indices where the path turns sharply enough to count as aiming at a
    new key, plus index 0 and the last index unconditionally.

    **This is the actual "corner detection" the spike needed.** A version that
    samples every point at a fixed rate and takes its nearest key, with no
    corner test at all, picks up every key a straight line between two *far
    apart* letters happens to cross — `h` to `e` on a QWERTY row, sampled that
    way with zero noise, reads back `h g t r e`, not `h e`, because the
    straight segment passes through `g`'s, `t`'s and `r`'s territory on the
    way. A real recognizer does not care that the path was briefly closer to
    `g`'s key than to `h`'s or `e`'s; it cares whether the path *turned*
    there, and along a straight segment it never does. Only the joints
    between segments turn, which is where the intended letters actually are.

    **The known failure this cannot fix**: a letter sitting almost exactly on
    the straight line between its own neighbours — `i` between `w` and `p` in
    `swipe`, `u` between `q` and `i` in `quick`, both on QWERTY's top row —
    produces a true turning angle near zero, at any noise level and any
    threshold, because the geometry really is that straight. No threshold
    tuning fixes this; it is a structural limit of corner detection, not a
    bug, and it is measured and named in the README rather than hidden.
    """
    if len(path) < 3:
        return list(range(len(path)))
    threshold = math.radians(angle_threshold_deg)
    idx = [0]
    for i in range(1, len(path) - 1):
        if _turning_angle(path[i - 1], path[i], path[i + 1]) >= threshold:
            idx.append(i)
    idx.append(len(path) - 1)
    return idx


def reduce_to_keys(
    path: list[tuple[float, float]],
    centers: dict[str, tuple[float, float]],
    *,
    angle_threshold_deg: float,
) -> tuple[str, ...]:
    """The sampled path collapsed to a key sequence: nearest key at each
    detected corner, consecutive duplicates collapsed. **Touch-down and
    touch-up are anchored** — `corner_indices` always keeps index 0 and the
    last index — because a real recognizer trusts where the finger landed
    and lifted more than any inferred turning point.
    """
    if not path:
        return ()
    corners = corner_indices(path, angle_threshold_deg=angle_threshold_deg)
    letters = [nearest_letter(path[i][0], path[i][1], centers) for i in corners]
    out: list[str] = []
    for letter in letters:
        if not out or out[-1] != letter:
            out.append(letter)
    return tuple(out)


def word_to_glide_code(
    word: str,
    centers: dict[str, tuple[float, float]],
    *,
    samples_per_segment: int,
    corner_cut: float,
    sigma: float,
    angle_threshold_deg: float,
    rng: random.Random,
) -> tuple[str, ...] | None:
    """The full pipeline: word -> waypoints -> noisy aim points -> smoothed
    path -> corner detection -> key sequence.

    `None` if the word has no letters this keyboard can place at all (an
    apostrophe, a digit, a script switch) — the same case `GlideLayout.code`
    returns `None` for, since both describe "no glide gesture reaches this".
    """
    points = waypoints(word, centers)
    if not points:
        return None
    noisy = perturb_waypoints(points, sigma, rng)
    path = curved_path(noisy, samples_per_segment=samples_per_segment, corner_cut=corner_cut)
    return reduce_to_keys(path, centers, angle_threshold_deg=angle_threshold_deg)
