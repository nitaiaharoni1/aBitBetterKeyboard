// Does the frame fingerprint still tell two conversations apart when the phone
// is sideways?
//
//   node Bar/screen-context/harness/frame-hash-landscape.mjs
//   KEEP=1 node ...        leave the renders in harness/frame-hash-landscape-out/
//
// **Nothing under `Bar/screen-context/` had ever swept a landscape frame**, so
// landscape's margin against `FrameReduction.Band.maximumOwnUI` was reasoning
// where portrait's was a reading. This is the same harness `frame-hash.mjs`
// runs, asked of a rotated screen, and it exists because the two orientations
// are not the same question:
//
//   * The cap is a **fraction** and the keyboard is **points**. An iPhone 17 Pro
//     rotated is 402 pt tall; a 375 pt landscape screen (iPhone SE, XS, 13 mini)
//     is the narrowest this ships to, and the same point height is a larger
//     fraction of it. At the 166 pt keyboard that was 0.4427 against the 0.4211
//     cap, `bottomCrop(ownUI:)` clamped, and the rows the clamp refused to crop
//     were rows of *our own keyboard* — this harness measured 30 of 30 frames
//     invalidated by our own Reply sweep there. NIT-114 took the keyboard to
//     154 pt, which is 0.4107 at 375 and under the cap on every width below.
//   * The moving part is different. Landscape draws no `ActionBanner`, so the
//     three shimmer lines the portrait sweep was built around are not there.
//     What runs for the whole of a read is `ControlSweep` on the Reply chip,
//     26 pt tall inside a 30 pt bar.
//
// So the variants are the portrait ones with our *landscape* keyboard, rendered
// once per shipping landscape height, and the crop per height is the one
// `FrameReduction.bottomCrop(ownUI:)` would actually produce there.
//
// Free: Playwright renders the frozen scenes and the reduction is arithmetic.
// No model call, no simulator, no network. See `Bar/drift/README.md` — the paid
// half of this corpus is the 30 multimodal calls, and none of them is here.
//
// Fails rather than skips: a scene that will not render, a reduction that comes
// back the wrong size, or a pair of shimmer phases that render identically all
// exit non-zero.

import { chromium } from "playwright";
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { scenes } from "../scenes.mjs";
import { renderLandscape, LANDSCAPE_DEVICE, OWN_KEYBOARD_LANDSCAPE } from "../skins.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "frame-hash-landscape-out");

const die = (m) => {
  console.error(`FAIL: ${m}`);
  process.exit(3);
};

// --- what the shipping code would crop -------------------------------------

/** `FrameReduction.Band`, restated. The cap is `368/874` and not 0.42; the
 *  difference is one point of keyboard and it has already cost this repo once. */
const BAND_TOP = 0.14;
const BAND_BOTTOM = 0.085;
const MAX_OWN_UI = 368 / 874;

/** `FrameReduction.bottomCrop(ownUI:)`, the same three lines. */
const bottomCrop = (fraction) =>
  !Number.isFinite(fraction) || fraction <= BAND_BOTTOM
    ? BAND_BOTTOM
    : Math.min(fraction, MAX_OWN_UI);

/** The landscape heights this keyboard ships to, which are the portrait
 *  *widths* of every iPhone the package's `iOS 17` floor still reaches. The
 *  narrowest and the widest are the ones that matter: the cap is a fraction of
 *  this number and `Theme.Metrics` spends points. */
const ALL_DEVICES = [
  { height: 375, phones: "SE 2/3, XS, 11 Pro, 12 mini, 13 mini" },
  { height: 390, phones: "12, 12 Pro, 13, 13 Pro, 14" },
  { height: 393, phones: "14 Pro, 15, 15 Pro, 16, 16e" },
  { height: 402, phones: "16 Pro, 17, 17 Pro" },
  { height: 430, phones: "14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus" },
  { height: 440, phones: "16 Pro Max, 17 Pro Max" },
];

/** `HEIGHTS=375,402` runs a subset. The renders are ~1.3 MB each and there are
 *  180 per height, so a `KEEP=1` run of all six is about 1.4 GB. */
const wanted = process.env.HEIGHTS?.split(",").map((s) => Number(s.trim()));
const DEVICES = wanted?.length
  ? ALL_DEVICES.filter((d) => wanted.includes(d.height))
  : ALL_DEVICES;
if (!DEVICES.length) die(`HEIGHTS matched none of ${ALL_DEVICES.map((d) => d.height).join(",")}`);

// --- the variants -----------------------------------------------------------
//
// The same substitutions `frame-hash.mjs` makes, so the two orientations are
// scored on identical pairs and a difference between them is the geometry
// rather than the corpus.

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

/** Our own landscape keyboard on screen with a model call running, which is the
 *  only state a reading is ever measured in: the reading exists because the user
 *  tapped Reply on this thing. */
const ourKeyboard = (scene, phase) => {
  const c = structuredClone(scene);
  c.keyboard = {
    ours: true,
    landscape: true,
    phase,
    lang: scene.keyboard?.lang ?? (scene.dir === "rtl" ? "he" : "en"),
    overlay: scene.keyboard?.overlay ?? false,
  };
  return c;
};

// --- the reduction ----------------------------------------------------------
//
// `FrameReduction`'s 32x64 greyscale, taken in the page so no image library is
// needed. Cropped into its own bitmap before it is resampled, for the reason
// `frame-hash.mjs` records: Skia builds its mip chain from the whole image, so a
// one-step downscale lets pixels outside the band bleed into every cell.

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

const exact = (r) => createHash("sha256").update(r).digest("hex");

// --- run --------------------------------------------------------------------

const browser = await chromium.launch();
const worker = await browser.newPage();
await worker.setContent("<!doctype html><meta charset=utf-8>", { waitUntil: "load" });

if (process.env.KEEP) await mkdir(OUT, { recursive: true });

const own = OWN_KEYBOARD_LANDSCAPE.totalHeight;
console.log(
  `deployment   macOS host (Playwright/Chromium), ${LANDSCAPE_DEVICE.pixelWidth} px wide, ${scenes.length} scenes`
);
console.log(
  `our keyboard ${own} pt = suggestion bar ${OWN_KEYBOARD_LANDSCAPE.suggestionHeight}` +
    ` + key area ${OWN_KEYBOARD_LANDSCAPE.keyAreaHeight}, no banner (Theme.Metrics.Landscape)`
);
console.log(`cap          FrameReduction.Band.maximumOwnUI = 368/874 = ${MAX_OWN_UI.toFixed(4)}`);
console.log();

const head = [
  "landscape height",
  "phones",
  "ours",
  "crop",
  "clamped by",
  "miss",
  "false",
  "own miss",
  "own false"
];
const widths = [18, 40, 8, 8, 12, 8, 8, 10, 11];
const row = (cells) =>
  cells.map((c, i) => (i < 2 ? String(c).padEnd(widths[i]) : String(c).padStart(widths[i]))).join("");
console.log(row(head));

let failed = false;
const detail = [];

for (const device of DEVICES) {
  const context = await browser.newContext({
    viewport: { width: LANDSCAPE_DEVICE.cssWidth, height: device.height },
    deviceScaleFactor: LANDSCAPE_DEVICE.scale,
  });
  const page = await context.newPage();

  const ourFraction = own / device.height;
  const crop = bottomCrop(ourFraction);
  // Points of our own keyboard the crop refuses to remove. Zero unless the
  // clamp bound; when it did, these are rows of our own bar — and the Reply
  // chip's sweep lives in the top 26 of the bar's 30.
  const leftInBand = Math.max(0, (ourFraction - crop) * device.height);

  const frames = [];
  for (const scene of scenes) {
    const shot = async (s, tag) => {
      await page.setContent(renderLandscape(s, device.height), { waitUntil: "load" });
      const png = await page.screenshot();
      if (process.env.KEEP)
        await writeFile(join(OUT, `${device.height}-${scene.id}-${tag}.png`), png);
      return png;
    };
    frames.push({
      id: scene.id,
      base: await shot(scene, "base"),
      last: await shot(newestOnly(scene, 11), "last"),
      chrome: await shot(chromeOnly(scene), "chrome"),
      panel: await shot(ourKeyboard(scene, 0.1), "panel"),
      panel2: await shot(ourKeyboard(scene, 0.6), "panel2"),
      panelLast: await shot(ourKeyboard(newestOnly(scene, 11), 0.1), "panellast"),
    });
  }
  if (frames.length < 30) die(`expected the 30 corpus scenes, rendered ${frames.length}`);
  if (frames.every((f) => f.panel.equals(f.panel2)))
    die("the two sweep phases render identically; the panel variant proves nothing");

  // A newest message drawn under a keyboard has no pixels to change, so its two
  // renders are byte-identical and no fingerprint of any width separates them.
  // Counted apart, exactly as the portrait harness counts `sl-05`.
  const occluded = frames.filter((f) => f.last.equals(f.base)).map((f) => f.id);
  const visible = frames.filter((f) => !occluded.includes(f.id));
  const ownOccluded = frames.filter((f) => f.panelLast.equals(f.panel)).map((f) => f.id);
  const ownVisible = frames.filter((f) => !ownOccluded.includes(f.id));

  // `base`/`last`/`chrome` are scored over the band used when no keyboard of
  // ours is up; the three `panel` renders over the band the producer derives
  // from what the keyboard published, which is the only band a reading is ever
  // measured against.
  const missed = [];
  const falsely = [];
  const ownMissed = [];
  const ownFalsely = [];
  for (const f of frames) {
    const host = [BAND_TOP, BAND_BOTTOM];
    const ours = [BAND_TOP, crop];
    const v = {
      base: exact(await reduce(worker, f.base, host)),
      last: exact(await reduce(worker, f.last, host)),
      chrome: exact(await reduce(worker, f.chrome, host)),
      panel: exact(await reduce(worker, f.panel, ours)),
      panel2: exact(await reduce(worker, f.panel2, ours)),
      panelLast: exact(await reduce(worker, f.panelLast, ours)),
    };
    if (!occluded.includes(f.id) && v.base === v.last) missed.push(f.id);
    if (v.base !== v.chrome) falsely.push(f.id);
    if (!ownOccluded.includes(f.id) && v.panel === v.panelLast) ownMissed.push(f.id);
    if (v.panel !== v.panel2) ownFalsely.push(f.id);
  }

  console.log(
    row([
      `${device.height} pt`,
      device.phones,
      `${(ourFraction * 100).toFixed(2)}%`,
      `${(crop * 100).toFixed(2)}%`,
      leftInBand > 0.05 ? `${leftInBand.toFixed(1)} pt ours` : "no",
      `${missed.length}/${visible.length}`,
      `${falsely.length}/${frames.length}`,
      `${ownMissed.length}/${ownVisible.length}`,
      `${ownFalsely.length}/${frames.length}`
    ])
  );
  detail.push({
    height: device.height,
    occluded,
    ownOccluded,
    missed,
    falsely,
    ownMissed,
    ownFalsely,
    leftInBand
  });
  if (ownMissed.length || ownFalsely.length) failed = true;
  await context.close();
}

await browser.close();

console.log();
for (const d of detail) {
  const notes = [];
  if (d.occluded.length) notes.push(`occluded ${d.occluded.join(" ")}`);
  if (d.ownOccluded.length) notes.push(`own occluded ${d.ownOccluded.join(" ")}`);
  if (d.missed.length) notes.push(`MISSED ${d.missed.join(" ")}`);
  if (d.falsely.length) notes.push(`FALSE ${d.falsely.join(" ")}`);
  if (d.ownMissed.length) notes.push(`OWN MISSED ${d.ownMissed.join(" ")}`);
  if (d.ownFalsely.length) notes.push(`OWN FALSE ${d.ownFalsely.join(" ")}`);
  console.log(`${String(d.height).padStart(3)} pt  ${notes.join("  |  ") || "clean"}`);
}

console.log();
console.log(
  failed
    ? "FAIL  at least one landscape height loses a conversation switch or is invalidated by our own sweep"
    : "PASS  every landscape height keeps 0 own misses and 0 own false invalidations"
);
process.exit(failed ? 1 : 0);
