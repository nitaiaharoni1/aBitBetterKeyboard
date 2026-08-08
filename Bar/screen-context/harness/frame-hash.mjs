// How well does a frame fingerprint tell two conversations apart?
//
// §6 condition 4 of `.claude/docs/screen-capture-design.md` is the only
// content-identity condition in the freshness gate: a reading stays offerable
// only while `record.frameHash == status.currentFrameHash`. The comparison is
// exact equality, so the failure that matters is not "close", it is *collision*:
// two different screens with the same value, which lets a reading about one
// conversation be offered for another. The opposite failure matters too: a value
// that moves when nothing the user cares about moved retires a good reading and
// costs a needless cloud read.
//
// The 30 corpus frames cannot answer either question on their own. They are
// thirty different scenes, and thirty different scenes look different. So this
// harness *builds* the near pairs. For every scene it renders four frames:
//
//   base    the scene as the corpus renders it
//   twin    every message's letters substituted inside its own script, so the
//           character count, word breaks, times, digits, bubble geometry and ink
//           density are identical and every glyph is different
//   last    the same substitution applied to the newest text message only
//   chrome  no message touched: the status-bar clock ticks over and the header
//           presence line changes ("online" -> "typing...")
//
// `last` is the collision test and the realistic one: switching to the next
// conversation in the same app, or a new message landing, changes a small part
// of a large frame. `chrome` is the false-invalidation test. `twin` is a sanity
// check that should never be close.
//
// Two knobs turned out to decide the answer and neither is obvious: which bands
// of the frame are cropped away before the reduction, and whether the value is a
// 64-bit perceptual hash or an exact hash of the reduction itself.
//
//   node Bar/screen-context/harness/frame-hash.mjs
//   KEEP=1 node ...        leave the rendered frames in harness/frame-hash-out/
//
// Fails rather than skips: a scene that will not render, a reduction that comes
// back the wrong size, or a run that produces no pairs exits non-zero.

import { chromium } from "playwright";
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { scenes } from "../scenes.mjs";
import { render, DEVICE, OWN_KEYBOARD } from "../skins.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "frame-hash-out");

const die = (m) => {
  console.error(`FAIL: ${m}`);
  process.exit(3);
};

// --- the variants -----------------------------------------------------------

// Letter-for-letter substitution inside the same script. Length, word breaks,
// punctuation, digits and clock times survive; every letter changes. This is the
// strongest honest form of "same layout, different conversation": anything
// weaker (a different sentence) also moves the line wrapping, and then a hash
// catches it for the wrong reason.
const HE_A = 0x05d0;
const HE_N = 0x05ea - 0x05d0 + 1;
const shift = (s, k) =>
  [...String(s)]
    .map((c) => {
      const p = c.codePointAt(0);
      if (p >= 0x05d0 && p <= 0x05ea) return String.fromCodePoint(HE_A + ((p - HE_A + k) % HE_N));
      if (p >= 97 && p <= 122) return String.fromCodePoint(97 + ((p - 97 + k) % 26));
      if (p >= 65 && p <= 90) return String.fromCodePoint(65 + ((p - 65 + k) % 26));
      return c;
    })
    .join("");

const twin = (scene, k) => {
  const c = structuredClone(scene);
  c.messages = c.messages.map((m) => (m.text == null ? m : { ...m, text: shift(m.text, k) }));
  return c;
};

const newestOnly = (scene, k) => {
  const c = structuredClone(scene);
  for (let i = c.messages.length - 1; i >= 0; i--) {
    const m = c.messages[i];
    if (m.kind && m.kind !== "text") continue;
    if (m.text == null) continue;
    c.messages[i] = { ...m, text: shift(m.text, k) };
    return c;
  }
  return die(`scene ${scene.id} has no text message to change`);
};

const chromeOnly = (scene) => {
  const c = structuredClone(scene);
  c.statusTime = c.statusTime === "9:41" ? "9:42" : "9:41";
  if (c.header) c.header.subtitle = c.header.subtitle === "typing..." ? "online" : "typing...";
  return c;
};

// The deployed state, which the four variants above never showed. A reading only
// ever exists because the user tapped Reply on *our* keyboard, so our keyboard is
// on screen for the whole read — with `AIResultPanel.loading` repainting three
// shimmer lines at `workingPhase += 0.03` every 16 ms. Rendering the host's stock
// keyboard instead is what let the harness report 0 false invalidations about a
// configuration in which every sampled frame got a new identity.
const ourKeyboard = (scene, phase) => {
  const c = structuredClone(scene);
  c.keyboard = {
    ours: true,
    phase,
    lang: scene.keyboard?.lang ?? (scene.dir === "rtl" ? "he" : "en"),
    // A scene whose keyboard is drawn over the thread keeps that: the host did
    // not relayout for it, so our keyboard covers the newest message too.
    overlay: scene.keyboard?.overlay ?? false,
  };
  return c;
};

// --- the reduction ----------------------------------------------------------

// The 32x64 greyscale reduction §2.2 of the design already budgets for, taken
// over the frame with the named bands removed. Done in the page so the resample
// is the browser's and no image library is needed.
const W = 32;
const H = 64;

async function reduce(page, png, [top, bottom]) {
  const bytes = await page.evaluate(
    async ({ b64, top, bottom, w, h }) => {
      const blob = await (await fetch(`data:image/png;base64,${b64}`)).blob();
      const full = await createImageBitmap(blob);
      const y = Math.round(full.height * top);
      const rows = Math.round(full.height * (1 - bottom)) - y;
      if (rows <= 0) throw new Error("crop leaves no rows");
      // **Cropped into its own bitmap before it is resampled, and that is not
      // tidiness.** Passing the source rectangle to `drawImage` and letting it
      // downscale in one step lets Skia build its mip chain from the *whole*
      // image, so pixels outside the band bleed into every output cell: with our
      // own keyboard on screen at two shimmer phases, two of the thirty scenes
      // moved a cell by one grey level in a row 1,300 px above the crop. The
      // shipping reduction is an integer box filter over `firstRow..<lastRow`
      // and cannot read outside the band at all, so that was the harness
      // disagreeing with the code it is supposed to be measuring.
      const bmp = await createImageBitmap(full, 0, y, full.width, rows);
      const c = new OffscreenCanvas(w, h);
      const g = c.getContext("2d", { willReadFrequently: true });
      g.imageSmoothingEnabled = true;
      g.imageSmoothingQuality = "high";
      g.drawImage(bmp, 0, 0, bmp.width, bmp.height, 0, 0, w, h);
      const d = g.getImageData(0, 0, w, h).data;
      const out = [];
      for (let i = 0; i < d.length; i += 4)
        out.push(Math.round(0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]));
      return out;
    },
    { b64: png.toString("base64"), top, bottom, w: W, h: H }
  );
  if (bytes.length !== W * H) die(`reduction returned ${bytes.length} samples, expected ${W * H}`);
  return Uint8Array.from(bytes);
}

// Exact identity: SHA-256 of the reduction. Moves if any of the 2,048 samples
// moves, and — unlike a perceptual hash — two of these cannot be compared for
// similarity at all, which is a privacy property as well as a matching one.
const exact = (r) => createHash("sha256").update(r).digest("hex");

// Perceptual: difference hash over an n x n regrid of the same reduction.
const dhash = (r, n) => {
  const cell = (row, col) => {
    let s = 0;
    let k = 0;
    const y0 = Math.floor((row * H) / n);
    const y1 = Math.max(y0 + 1, Math.floor(((row + 1) * H) / n));
    const x0 = Math.floor((col * W) / (n + 1));
    const x1 = Math.max(x0 + 1, Math.floor(((col + 1) * W) / (n + 1)));
    for (let y = y0; y < y1; y++)
      for (let x = x0; x < x1; x++) {
        s += r[y * W + x];
        k++;
      }
    return s / k;
  };
  const bits = [];
  for (let row = 0; row < n; row++)
    for (let col = 0; col < n; col++) bits.push(cell(row, col) > cell(row, col + 1) ? 1 : 0);
  return bits;
};
const hamming = (a, b) => a.reduce((s, v, i) => s + (v === b[i] ? 0 : 1), 0);

// --- bands ------------------------------------------------------------------
//
// Fractions of frame height removed from the top and from the bottom. The
// `VisionScreenReader.Band` row is the band that class already filters message
// lines to: statusBar 0.935, navigationBar 0.86 and composer 0.085 in Vision's
// bottom-up coordinates are the top 14% and the bottom 8.5% here.
const OURS = OWN_KEYBOARD.screenFraction; // 292 / 874 = 0.334
const BANDS = {
  "no crop": [0.0, 0.0],
  "status only        (top 6.5%)": [0.065, 0.0],
  "status + composer  (top 6.5% / bottom 8.5%)": [0.065, 0.085],
  "status + keyboard  (top 6.5% / bottom 45%)": [0.065, 0.45],
  "VisionScreenReader.Band (top 14% / bottom 8.5%)": [0.14, 0.085],
  // The band the producer uses while our own keyboard is on screen, which is
  // every frame a reading is ever measured against. The last row is the cap
  // `FrameReduction.Band.maximumOwnUI` holds a bad claim to, measured so the cap
  // is a number rather than a hope.
  [`ours excluded (top 14% / bottom ${(OURS * 100).toFixed(1)}%)`]: [0.14, OURS],
  "ours excluded, at the cap (top 14% / bottom 40%)": [0.14, 0.4],
};

// --- run --------------------------------------------------------------------

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: DEVICE.cssWidth, height: DEVICE.cssHeight },
  deviceScaleFactor: DEVICE.scale,
});
const page = await context.newPage();
const worker = await context.newPage();
await worker.setContent("<!doctype html><meta charset=utf-8>", { waitUntil: "load" });

if (process.env.KEEP) await mkdir(OUT, { recursive: true });

const frames = [];
for (const scene of scenes) {
  const shot = async (s, tag) => {
    await page.setContent(render(s), { waitUntil: "load" });
    const png = await page.screenshot();
    if (process.env.KEEP) await writeFile(join(OUT, `${scene.id}-${tag}.png`), png);
    return png;
  };
  frames.push({
    id: scene.id,
    app: scene.app,
    base: await shot(scene, "base"),
    twin: await shot(twin(scene, 7), "twin"),
    last: await shot(newestOnly(scene, 11), "last"),
    chrome: await shot(chromeOnly(scene), "chrome"),
    // The same scene with our own keyboard up, at two shimmer phases, plus the
    // conversation switch under it.
    panel: await shot(ourKeyboard(scene, 0.1), "panel"),
    panel2: await shot(ourKeyboard(scene, 0.6), "panel2"),
    panelLast: await shot(ourKeyboard(newestOnly(scene, 11), 0.1), "panellast"),
  });
}
if (frames.length < 30) die(`expected the 30 corpus scenes, rendered ${frames.length}`);

// A frame whose newest message is drawn under a keyboard has no pixels to
// change, so `last` is byte-identical to `base` and no fingerprint can separate
// them. That is a property of the screen, not of the fingerprint, and it is
// counted apart rather than scored against any row. Counted twice, because our
// keyboard occludes a different set of screens from the host's: a scene rendered
// without a keyboard at all gets one when ours comes up.
const occluded = frames.filter((f) => f.last.equals(f.base)).map((f) => f.id);
const visible = frames.filter((f) => !occluded.includes(f.id));
const ownOccluded = frames.filter((f) => f.panelLast.equals(f.panel)).map((f) => f.id);
const ownVisible = frames.filter((f) => !ownOccluded.includes(f.id));
if (frames.every((f) => f.panel.equals(f.panel2))) {
  die("the two shimmer phases render identically; the panel variant proves nothing");
}

console.log(`deployment   macOS host (Playwright/Chromium), ${DEVICE.pixelWidth}x${DEVICE.pixelHeight}`);
console.log(`frames       ${frames.length} scenes x 7 renders, reduced to ${W}x${H} greyscale`);
console.log(
  `occluded     ${occluded.length ? occluded.join(" ") : "none"}  (newest message under the host keyboard; base and last are byte-identical)`
);
console.log(
  `own occluded ${ownOccluded.length ? ownOccluded.join(" ") : "none"}  (newest message under *our* keyboard; panel and panellast are byte-identical)`
);
console.log(
  `our keyboard ${OWN_KEYBOARD.totalHeight} pt of ${DEVICE.cssHeight} pt = ${(OURS * 100).toFixed(1)}% of the screen, shimmer at phase 0.10 and 0.60`
);
console.log();
const head = ["band", "value", "miss", "false", "own miss", "own false", "twin min", "same-app min"];
const widths = [50, 12, 6, 7, 10, 11, 10, 14];
const row = (cells) => cells.map((c, i) => (i === 0 ? String(c).padEnd(widths[i]) : String(c).padStart(widths[i]))).join("");
console.log(row(head));

for (const [label, band] of Object.entries(BANDS)) {
  const R = new Map();
  for (const f of frames)
    R.set(f.id, {
      base: await reduce(worker, f.base, band),
      twin: await reduce(worker, f.twin, band),
      last: await reduce(worker, f.last, band),
      chrome: await reduce(worker, f.chrome, band),
      panel: await reduce(worker, f.panel, band),
      panel2: await reduce(worker, f.panel2, band),
      panelLast: await reduce(worker, f.panelLast, band),
    });

  const values = [
    ["sha256(2048B)", (r) => exact(r), (a, b) => (a === b ? 0 : 1)],
    ["dHash 64b", (r) => dhash(r, 8), hamming],
    ["dHash 256b", (r) => dhash(r, 16), hamming],
  ];
  for (const [name, of, dist] of values) {
    const V = new Map(
      [...R].map(([id, v]) => [
        id,
        {
          base: of(v.base),
          twin: of(v.twin),
          last: of(v.last),
          chrome: of(v.chrome),
          panel: of(v.panel),
          panel2: of(v.panel2),
          panelLast: of(v.panelLast),
        },
      ])
    );
    // miss  = newest message changed and the value did not
    const miss = visible.filter((f) => dist(V.get(f.id).base, V.get(f.id).last) === 0).length;
    // false = nothing but chrome changed and the value did
    const wrong = frames.filter((f) => dist(V.get(f.id).base, V.get(f.id).chrome) !== 0).length;
    // The same two questions asked of the deployed state: our own keyboard is up,
    // its result panel is loading, and the only thing that changed between the two
    // frames is either the newest message (must separate) or our shimmer phase
    // (must not).
    const ownMiss = ownVisible.filter((f) => dist(V.get(f.id).panel, V.get(f.id).panelLast) === 0).length;
    const ownWrong = frames.filter((f) => dist(V.get(f.id).panel, V.get(f.id).panel2) !== 0).length;
    const twinMin = Math.min(...visible.map((f) => dist(V.get(f.id).base, V.get(f.id).twin)));
    const sameApp = [];
    for (let i = 0; i < visible.length; i++)
      for (let j = i + 1; j < visible.length; j++)
        if (visible[i].app === visible[j].app) sameApp.push(dist(V.get(visible[i].id).base, V.get(visible[j].id).base));
    if (!sameApp.length) die("no same-app pairs to compare");
    console.log(
      row([
        label,
        name,
        `${miss}/${visible.length}`,
        `${wrong}/${frames.length}`,
        `${ownMiss}/${ownVisible.length}`,
        `${ownWrong}/${frames.length}`,
        twinMin,
        Math.min(...sameApp),
      ])
    );
  }
}

await browser.close();
console.log();
console.log("miss   pairs that differ only in the newest message's glyphs and are not");
console.log("       separated. §6 condition 4 is an exact-equality test, so every one is a");
console.log("       reading that stays offerable across a conversation switch. Must be 0.");
console.log("false  frames where only the clock and the presence line moved and the value");
console.log("       moved with them. Every one retires a good reading and buys a needless");
console.log("       cloud read. Must be 0.");
console.log("own    the same two questions asked of the deployed state: our own keyboard up,");
console.log("       its result panel loading. `own miss` is a conversation switch under our");
console.log("       panel that the value fails to separate; `own false` is our own shimmer");
console.log("       moving the value. Both must be 0. A non-zero `own false` is the shipping");
console.log("       blocker this variant was added for: the gate refuses the answer to the");
console.log("       tap that paid for it, twelve seconds after spending the cloud call.");
console.log("The last two columns are sanity: a wholly different conversation and a");
console.log("different scene in the same app should both be far away, never near. For the");
console.log("sha256 row the distance is boolean, so those two columns can only read 0 or 1");
console.log("and 1 is the pass; only the Hamming rows carry a margin there.");
