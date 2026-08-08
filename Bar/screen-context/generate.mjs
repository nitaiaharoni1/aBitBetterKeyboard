// Renders every scene at iPhone 17 Pro resolution and derives ground truth from
// the laid-out page.
//
// The ground truth is measured, not typed. After the screenshot we walk the DOM
// line by line and ask, per line: is it inside the viewport, and does a hit test
// at its centre still reach it? A line that fails either test is off screen or
// under the keyboard, and it does not go into the ground truth no matter what
// the scene file says. That is what makes the scrolled-off-top and
// keyboard-occlusion cases trustworthy: the corpus claims a message is
// unreadable only because it measured that it is.
//
//   node generate.mjs

import { chromium } from "playwright";
import { mkdir, writeFile, readdir, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { scenes } from "./scenes.mjs";
import { render, DEVICE } from "./skins.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const IMAGES = join(HERE, "images");

const HEBREW = /[֐-׿]/;
const strip = (s) => s.replace(/\s+/g, "");
const langOf = (t) => (HEBREW.test(t) ? "hebrew" : "english");
const scriptOf = (t) => {
  const he = HEBREW.test(t);
  const la = /[A-Za-z]/.test(t);
  return he && la ? "mixed" : he ? "hebrew" : "latin";
};

/** Kinds that carry a body a person could reply to. */
const REPLIABLE = new Set([undefined, "text"]);

// --- in-page measurement ----------------------------------------------------

/* eslint-env browser */
function measure() {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const seg = new Intl.Segmenter("en", { granularity: "grapheme" });

  const lineBoxes = (el) => {
    const lines = [];
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    const range = document.createRange();
    let node;
    while ((node = walker.nextNode())) {
      const s = node.nodeValue;
      if (!s.trim()) continue;
      const bounds = [0];
      for (const g of seg.segment(s)) bounds.push(g.index + g.segment.length);
      let cur = null;
      for (let i = 0; i < bounds.length - 1; i++) {
        const piece = s.slice(bounds[i], bounds[i + 1]);
        range.setStart(node, bounds[i]);
        range.setEnd(node, bounds[i + 1]);
        const r = range.getClientRects()[0];
        if (!r || r.width === 0) {
          if (cur) cur.text += piece;
          continue;
        }
        if (cur && Math.abs(r.top - cur.top) < 3) {
          cur.text += piece;
          cur.left = Math.min(cur.left, r.left);
          cur.right = Math.max(cur.right, r.right);
          cur.bottom = Math.max(cur.bottom, r.bottom);
        } else {
          if (cur) lines.push(cur);
          cur = { text: piece, top: r.top, bottom: r.bottom, left: r.left, right: r.right };
        }
      }
      if (cur) lines.push(cur);
    }
    return lines;
  };

  // A message scrolled off the top of the thread is still inside the viewport;
  // it is the thread's own overflow:hidden that makes it invisible. So the clip
  // box is the viewport intersected with every scrolling ancestor.
  const clipBox = (el) => {
    let box = { top: 0, left: 0, bottom: vh, right: vw };
    for (let n = el.parentElement; n; n = n.parentElement) {
      const st = getComputedStyle(n);
      if (st.overflowX === "visible" && st.overflowY === "visible") continue;
      const b = n.getBoundingClientRect();
      box = {
        top: Math.max(box.top, b.top),
        left: Math.max(box.left, b.left),
        bottom: Math.min(box.bottom, b.bottom),
        right: Math.min(box.right, b.right),
      };
    }
    return box;
  };

  // The keyboard is not an ancestor of the text it covers, so a hit test that
  // lands anywhere outside the text's own subtree (or its immediate bubble)
  // means something is painted on top.
  const belongs = (el, hit) => {
    if (!hit || hit === document.body || hit === document.documentElement) return false;
    if (hit === el || el.contains(hit)) return true;
    let n = el.parentElement;
    for (let d = 0; n && d < 3; d++, n = n.parentElement) if (n === hit) return true;
    return false;
  };

  const classify = (el, box, l) => {
    const h = l.bottom - l.top;
    const w = l.right - l.left;
    if (h <= 0 || w <= 0) return "clipped";
    const dy = Math.max(0, Math.min(l.bottom, box.bottom) - Math.max(l.top, box.top)) / h;
    const dx = Math.max(0, Math.min(l.right, box.right) - Math.max(l.left, box.left)) / w;
    if (dy * dx < 0.6) return "clipped";
    const y = (Math.max(l.top, box.top) + Math.min(l.bottom, box.bottom)) / 2;
    let hits = 0;
    for (const f of [0.2, 0.5, 0.8]) {
      const x = Math.min(box.right - 1, Math.max(box.left, l.left + w * f));
      if (belongs(el, document.elementFromPoint(x, y))) hits++;
    }
    return hits >= 2 ? "visible" : "occluded";
  };

  const out = [];
  for (const el of document.querySelectorAll("[data-role]")) {
    const visible = [];
    const hidden = [];
    const box = clipBox(el);
    for (const l of lineBoxes(el)) {
      const verdict = classify(el, box, l);
      if (verdict === "visible") visible.push({ text: l.text, top: l.top, bottom: l.bottom });
      else hidden.push({ text: l.text, reason: verdict });
    }
    if (!visible.length && !hidden.length) continue;
    out.push({
      role: el.dataset.role,
      mid: el.dataset.mid ?? null,
      from: el.dataset.from ?? null,
      sender: el.dataset.sender || null,
      kind: el.dataset.kind ?? null,
      visible,
      hidden,
    });
  }
  return out;
}

// --- shaping ----------------------------------------------------------------

/** OCR returns lines, not elements. Fuse runs that sit on the same row, which is
 *  how "Daniel Cohen", "10:24 AM" and an avatar initial arrive from Vision as one
 *  line of text immediately above the message body. Baselines are compared by
 *  vertical overlap rather than by top edge, because a 15px name and a 12px
 *  timestamp share a baseline while starting at different heights. */
function fuseLines(records) {
  const rows = [];
  for (const rec of records) {
    for (const l of rec.visible) {
      const last = rows[rows.length - 1];
      const overlap = last
        ? Math.max(0, Math.min(last.bottom, l.bottom) - Math.max(last.top, l.top)) /
          Math.min(last.bottom - last.top, l.bottom - l.top)
        : 0;
      if (last && overlap >= 0.5) {
        last.parts.push(l.text.trim());
        last.top = Math.min(last.top, l.top);
        last.bottom = Math.max(last.bottom, l.bottom);
      } else {
        rows.push({ top: l.top, bottom: l.bottom, parts: [l.text.trim()] });
      }
    }
  }
  return rows.map((r) => r.parts.filter(Boolean).join("  ")).filter(Boolean);
}

const joinVisible = (rec) => rec.visible.map((l) => l.text.trim()).filter(Boolean).join(" ");

function buildTruth(scene, records) {
  const bodies = records.filter((r) => r.role === "msg");
  const byMid = new Map(bodies.map((r) => [r.mid, r]));

  const chrome = records
    .filter((r) => r.role === "chrome" && r.visible.length)
    .map(joinVisible)
    .filter(Boolean);

  const clipped = records.flatMap((r) =>
    r.hidden.map((h) => ({ text: h.text.trim(), reason: h.reason, role: r.role }))
  ).filter((c) => c.text);

  // A scene may only claim a hard case it can prove. "scrolled-off-top" with
  // nothing actually clipped would be a lie the critic could not detect.
  if (scene.hardCases.some((c) => c.startsWith("scrolled-off-top")) && !clipped.some((c) => c.reason === "clipped"))
    throw new Error(`${scene.id}: claims scrolled-off-top but every line fits on screen`);
  if (scene.hardCases.includes("keyboard-occludes-newest-message") && !clipped.some((c) => c.reason === "occluded"))
    throw new Error(`${scene.id}: claims keyboard occlusion but nothing is covered`);

  const ov = scene.expectedOverride ?? {};

  // Which scene message is the answer: an explicit target, else the newest
  // incoming one with a body.
  let targetIndex = scene.messages.findIndex((m) => m.target);
  if (targetIndex < 0) {
    for (let i = scene.messages.length - 1; i >= 0; i--) {
      const m = scene.messages[i];
      if (m.from === "them" && REPLIABLE.has(m.kind)) {
        targetIndex = i;
        break;
      }
    }
  }

  // If the corpus says the keyboard hides the newest messages, prove that every
  // message below the target really is unreadable.
  if (scene.hardCases.includes("keyboard-occludes-newest-message")) {
    for (let i = targetIndex + 1; i < scene.messages.length; i++) {
      const rec = byMid.get(`m${i}`);
      if (rec && rec.visible.length)
        throw new Error(`${scene.id}: m${i} is below the target but still readable on screen`);
    }
  }

  const lastReal = [...scene.messages].reverse().find((m) => m.from === "them" || m.from === "me");
  const lastMessageIsOutgoing = lastReal?.from === "me";

  let expected = null;
  if (!ov.none && targetIndex >= 0) {
    const m = scene.messages[targetIndex];
    const rec = byMid.get(`m${targetIndex}`);
    if (!rec) throw new Error(`${scene.id}: expected message m${targetIndex} never rendered`);

    const seen = joinVisible(rec);
    if (ov.truncatedAtTop) {
      if (!strip(m.text).endsWith(strip(seen)) || !rec.hidden.length)
        throw new Error(`${scene.id}: message was declared truncated at top but renders whole`);
    } else if (strip(seen) !== strip(m.text)) {
      throw new Error(
        `${scene.id}: expected message does not match what is on screen\n  want: ${m.text}\n  got:  ${seen}`
      );
    }

    expected = {
      sender: m.sender,
      message: seen,
      language: langOf(seen),
      script: scriptOf(seen),
      messageLines: rec.visible.map((l) => l.text.trim()).filter(Boolean),
      fullyVisible: rec.hidden.length === 0,
    };
    if (ov.truncatedAtTop) {
      expected.truncatedAtTop = true;
      expected.completeMessageText = m.text;
    }
  }

  return {
    id: scene.id,
    file: `images/${scene.id}.png`,
    app: scene.app,
    appearance: scene.appearance,
    language: scene.language,
    layoutDirection: scene.dir,
    keyboardVisible: Boolean(scene.keyboard),
    hardCases: scene.hardCases,
    notes: scene.notes,

    // What a perfect OCR pass returns: every visible line, in reading order.
    fullText: fuseLines(records).join("\n"),

    // The three fields the product actually needs.
    expected,
    lastMessageIsOutgoing,
    ...(ov.reason ? { expectedReason: ov.reason } : {}),
    ...(ov.none ? { noRepliableText: true } : {}),
    ...(ov.staleIncomingText ? { staleIncomingText: ov.staleIncomingText } : {}),

    // Text a correct implementation must never return as the message.
    chrome,
    traps: scene.traps ?? [],

    // Measured as not readable: past the viewport edge or under the keyboard.
    notOnScreen: clipped,

    // Every message body the screen contains, for scoring partial credit.
    messagesOnScreen: bodies.map((r) => ({
      from: r.from,
      sender: r.sender,
      text: joinVisible(r),
      fullyVisible: r.hidden.length === 0,
    })),
  };
}

// --- png header -------------------------------------------------------------

function pngSize(buf) {
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

// --- run --------------------------------------------------------------------

async function main() {
  await rm(IMAGES, { recursive: true, force: true });
  await mkdir(IMAGES, { recursive: true });

  const ids = new Set();
  for (const s of scenes) {
    if (ids.has(s.id)) throw new Error(`duplicate scene id ${s.id}`);
    ids.add(s.id);
  }

  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: DEVICE.cssWidth, height: DEVICE.cssHeight },
    deviceScaleFactor: DEVICE.scale,
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  const page = await context.newPage();

  const images = [];
  for (const scene of scenes) {
    await page.setContent(render(scene), { waitUntil: "load" });
    await page.evaluate(() => document.fonts.ready);
    const shot = await page.screenshot({ path: join(IMAGES, `${scene.id}.png`) });

    const size = pngSize(shot);
    if (size.width !== DEVICE.pixelWidth || size.height !== DEVICE.pixelHeight)
      throw new Error(`${scene.id}: rendered ${size.width}x${size.height}`);

    const records = await page.evaluate(measure);
    images.push(buildTruth(scene, records));
    process.stdout.write(`${scene.id} `);
  }
  process.stdout.write("\n");
  await browser.close();

  const tally = (key) =>
    images.reduce((acc, i) => ((acc[i[key]] = (acc[i[key]] ?? 0) + 1), acc), {});

  const hardCaseCounts = {};
  for (const i of images) for (const c of i.hardCases) hardCaseCounts[c] = (hardCaseCounts[c] ?? 0) + 1;

  const doc = {
    device: DEVICE,
    generator: "node generate.mjs",
    counts: {
      images: images.length,
      byApp: tally("app"),
      byAppearance: tally("appearance"),
      byLanguage: tally("language"),
      byHardCase: Object.fromEntries(Object.entries(hardCaseCounts).sort()),
      withKeyboard: images.filter((i) => i.keyboardVisible).length,
      lastMessageOutgoing: images.filter((i) => i.lastMessageIsOutgoing).length,
      noRepliableText: images.filter((i) => i.noRepliableText).length,
    },
    fields: {
      fullText: "Every line of text visible on screen, in reading order. What a perfect OCR pass returns.",
      expected:
        "The three fields the product needs: sender of the newest readable incoming message, that " +
        "message's text, and its language. null when the screen holds nothing worth replying to.",
      "expected.script": "hebrew | latin | mixed. Distinct from language, which is what the keyboard switches to.",
      chrome:
        "Text on screen that is not message content: nav bars, sender labels, timestamps, receipts, " +
        "reaction counts, keyboard key caps, composer placeholders. A correct implementation reads " +
        "these but never returns one as the message.",
      traps: "The specific runs of chrome most likely to be returned instead of the message, and why.",
      notOnScreen:
        "Text measured as unreadable: clipped by the viewport edge, or covered by the keyboard. " +
        "An implementation that returns any of this is hallucinating.",
      messagesOnScreen: "Every message body on screen, for partial credit.",
      lastMessageIsOutgoing: "The bottom-most message is the user's own. The answer is further up.",
    },
    images,
  };

  await writeFile(join(HERE, "ground-truth.json"), JSON.stringify(doc, null, 2) + "\n");

  const written = (await readdir(IMAGES)).filter((f) => f.endsWith(".png"));
  console.log(`${written.length} images -> images/`);
  console.log(JSON.stringify(doc.counts, null, 2));
}

await main();
