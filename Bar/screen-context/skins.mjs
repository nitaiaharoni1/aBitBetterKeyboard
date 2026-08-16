// Faithful renderings of the chat UIs the keyboard has to read over the user's
// shoulder. Not pixel-identical to the real apps, but the OCR problem is the
// same shape: same type sizes, same bubble-on-background contrast, same RTL
// alignment, same chrome sitting inches from the text that matters.
//
// Every run of text is tagged with data-role:
//   data-role="msg"    the body of a message, the thing a reply is written to
//   data-role="chrome" everything else — nav bars, timestamps, sender labels,
//                      reaction counts, keyboard keys, status bar, composers
// generate.mjs reads those tags back out of the laid-out page, so ground truth
// is measured from the rendered pixels rather than typed twice.

export const DEVICE = {
  name: "iPhone 17 Pro",
  cssWidth: 402,
  cssHeight: 874,
  scale: 3,
  pixelWidth: 1206,
  pixelHeight: 2622,
};

const esc = (s) =>
  String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/** A run of chrome: read by OCR, never the answer. */
const ch = (text, cls = "") =>
  text === "" || text == null ? "" : `<span class="${cls}" data-role="chrome">${esc(text)}</span>`;

/** A run of message body. */
const body = (m, id, text) =>
  `<span class="txt" data-role="msg" data-mid="${id}" data-from="${m.from}"` +
  ` data-sender="${esc(m.sender ?? "")}" data-kind="${m.kind ?? "text"}">${esc(text)}</span>`;

const hasHebrew = (s) => /[֐-׿]/.test(s ?? "");

// ---------------------------------------------------------------------------
// Shared shell: status bar, Dynamic Island, home indicator, keyboard
// ---------------------------------------------------------------------------

const BASE_CSS = `
*{margin:0;padding:0;box-sizing:border-box;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
html,body{width:${DEVICE.cssWidth}px;height:${DEVICE.cssHeight}px;overflow:hidden}
body{font-family:-apple-system,"SF Pro Text","SF Pro","Helvetica Neue",Helvetica,Arial,sans-serif;
  font-size:17px;line-height:1.29}
.screen{position:relative;width:${DEVICE.cssWidth}px;height:${DEVICE.cssHeight}px;
  display:flex;flex-direction:column;overflow:hidden}
.island{position:absolute;top:11px;left:50%;transform:translateX(-50%);
  width:125px;height:37px;border-radius:19px;background:#000;z-index:60}
.statusbar{flex:0 0 62px;display:flex;align-items:flex-end;justify-content:space-between;
  padding:0 0 9px;position:relative;z-index:50}
.sb-time{width:120px;text-align:center;font-size:16px;font-weight:600;letter-spacing:-.2px;padding-left:4px}
.sb-icons{width:120px;display:flex;align-items:center;justify-content:center;gap:6px;padding-right:8px}
.home-ind{position:absolute;bottom:9px;left:50%;transform:translateX(-50%);
  width:140px;height:5px;border-radius:3px;z-index:55;pointer-events:none}
.thread{flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end}
.thread-inner{display:flex;flex-direction:column}
.txt{white-space:pre-wrap;overflow-wrap:break-word}
.i{flex:0 0 auto;display:block}
[dir="rtl"] .chev{transform:scaleX(-1)}
.kb{flex:0 0 auto;z-index:40;padding-bottom:26px;user-select:none}
.kb.overlay{position:absolute;left:0;right:0;bottom:0}
.kb-sugg{height:44px;display:flex;align-items:center}
.kb-sugg span{flex:1;text-align:center;font-size:16px}
.kb-row{display:flex;justify-content:center;gap:6px;margin-bottom:11px}
.kb-key{width:31px;height:42px;border-radius:5px;display:flex;align-items:center;justify-content:center;
  font-size:22px;font-weight:400}
.kb-key.wide{width:42px;font-size:15px}
.kb-key.space{width:172px;font-size:15px}
.kb-key.act{width:88px;font-size:15px}
.kb-key.plain{background:none!important;box-shadow:none!important}
`;

const SB_ICONS = `
<svg width="19" height="12" viewBox="0 0 19 12" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="6" width="3" height="6" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
<svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor"><path d="M8.5 11.4 6.2 9a3.3 3.3 0 0 1 4.6 0zM4.2 7.1 2.6 5.5a8.4 8.4 0 0 1 11.8 0l-1.6 1.6a6.1 6.1 0 0 0-8.6 0zM.6 3.5A11.5 11.5 0 0 1 16.4 3.5l-1.6 1.6a9.2 9.2 0 0 0-12.6 0z"/></svg>
<svg width="27" height="13" viewBox="0 0 27 13" fill="none"><rect x=".5" y=".5" width="22" height="12" rx="3.8" stroke="currentColor" stroke-opacity=".4"/><rect x="2" y="2" width="19" height="9" rx="2.5" fill="currentColor"/><path d="M24.5 4.3a2.4 2.4 0 0 1 0 4.4z" fill="currentColor" fill-opacity=".4"/></svg>`;

// iOS never mirrors the status bar: the clock stays left of the icons even in
// a right-to-left app, so it is pinned to ltr regardless of the thread.
function statusBar(time = "9:41") {
  return `<div class="island"></div>
<div class="statusbar" dir="ltr">${ch(time, "sb-time")}<div class="sb-icons">${SB_ICONS}</div></div>`;
}

/** Nav-bar and composer glyphs. Drawn rather than set as emoji: the real apps
 *  use vector icons, and OCR must not find words where the app shows a shape. */
const ICON = {
  video: `<svg class="i" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="2.5" y="6.5" width="12" height="11" rx="2.5"/><path d="M14.5 11l6-3.5v9l-6-3.5z" stroke-linejoin="round"/></svg>`,
  phone: `<svg class="i" width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M6.6 3.2c.7-.5 1.7-.3 2.2.4l1.7 2.4c.4.6.3 1.4-.2 1.9l-1 1a12 12 0 0 0 4.8 4.8l1-1c.5-.5 1.3-.6 1.9-.2l2.4 1.7c.7.5.9 1.5.4 2.2l-1.1 1.5c-.6.8-1.6 1.2-2.6 1A17 17 0 0 1 4.1 7.4c-.2-1 .2-2 1-2.6z"/></svg>`,
  mic: `<svg class="i" width="21" height="21" viewBox="0 0 24 24" fill="currentColor"><rect x="9" y="2.5" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round"/><path d="M12 17.5v4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>`,
  plus: `<svg class="i" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>`,
  camera: `<svg class="i" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M3 8.5h3l1.5-2h9L18 8.5h3v10H3z" stroke-linejoin="round"/><circle cx="12" cy="13" r="3.3"/></svg>`,
  clip: `<svg class="i" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M16.5 7.5 9 15a2.8 2.8 0 0 0 4 4l7-7a5 5 0 0 0-7-7l-7 7a7.2 7.2 0 0 0 10 10l5.5-5.5"/></svg>`,
  smiley: `<svg class="i" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="9"/><path d="M8.5 14.5a4.5 4.5 0 0 0 7 0" stroke-linecap="round"/><circle cx="9" cy="9.8" r="1.1" fill="currentColor" stroke="none"/><circle cx="15" cy="9.8" r="1.1" fill="currentColor" stroke="none"/></svg>`,
  play: `<svg class="i" width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5 19 12 7 19.5z"/></svg>`,
  send: `<svg class="i" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5.5 11.5 12 5l6.5 6.5"/></svg>`,
  menu: `<svg class="i" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>`,
  at: `<svg class="i" width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="3.6"/><path d="M15.6 12v2.2a2.6 2.6 0 0 0 5.2 0V12a8.8 8.8 0 1 0-3.5 7" stroke-linecap="round"/></svg>`,
  flag: `<svg class="i" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M5.5 21V4.5c3.5-2 7 2 10.5 0v9c-3.5 2-7-2-10.5 0"/></svg>`,
  trash: `<svg class="i" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M4.5 6.5h15M9.5 6.5V4h5v2.5M6.5 6.5 7.5 21h9l1-14.5"/></svg>`,
  folder: `<svg class="i" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M3 6.5h6l2 2.5h10V19H3z"/></svg>`,
  reply: `<svg class="i" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6 3.5 11 9 16v-3c6 0 9.5 2 11.5 6 .5-7-3.5-11-11.5-11z"/></svg>`,
  compose: `<svg class="i" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L20 8l-4-4L4 16z"/></svg>`,
  chev: `<svg class="i chev" width="12" height="20" viewBox="0 0 12 20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 2 2.5 10 9 18"/></svg>`,
};

const homeIndicator = () => `<div class="home-ind"></div>`;

const KB_ROWS = {
  en: [
    [..."qwertyuiop"],
    [..."asdfghjkl"],
    [..."zxcvbnm"],
  ],
  he: [
    [..."קראטוןםפ"],
    [..."שדגכעיחלךף"],
    [..."זסבהנמצתץ"],
  ],
};

const KB_SUGGESTIONS = {
  en: ["I", "The", "Sure"],
  he: ["אני", "תודה", "בסדר"],
};

// ---------------------------------------------------------------------------
// Our own keyboard
// ---------------------------------------------------------------------------

/** `Theme.Metrics`, in points, as the keyboard extension asks the host for them:
 *  context strip 30 + suggestion bar 46 + key area (42*4 + 12*3 + 8 + 4) 216. */
export const OWN_KEYBOARD = {
  stripHeight: 30,
  suggestionHeight: 46,
  keyAreaHeight: 216,
  get totalHeight() {
    return this.stripHeight + this.suggestionHeight + this.keyAreaHeight;
  },
  /** What `CaptureIntent.ownUIHeightPermille` carries on this device. */
  get screenFraction() {
    return this.totalHeight / DEVICE.cssHeight;
  },
};

const OWN_CSS = `
.own{--bg:#D1D3D9;--panel:#E6E8ED;--label:#000;--sub:#3C3C43;--fn:#ADB3BE;--txt2:#60636B;--txt1:#0B0B0F}
[data-appearance="dark"] .own{--bg:#161618;--panel:#1C1C1F;--label:#fff;--sub:#C7C7CC;--fn:#2C2C2E;
  --txt2:#9C9CA6;--txt1:#F5F5F7}
.own{flex:0 0 auto;z-index:45;height:${OWN_KEYBOARD.totalHeight}px;background:var(--bg);
  color:var(--label);display:flex;flex-direction:column;direction:ltr}
.own.overlay{position:absolute;left:0;right:0;bottom:0}
.own .strip{flex:0 0 ${OWN_KEYBOARD.stripHeight}px;background:var(--panel);display:flex;align-items:center;
  gap:8px;padding:0 12px;border-bottom:.5px solid rgba(60,60,67,.15)}
.own .dot{width:7px;height:7px;border-radius:50%;background:#FF453A;flex:0 0 7px}
.own .who{font-size:12px;font-weight:600;color:var(--label);white-space:nowrap}
.own .said{font-size:12px;color:var(--sub);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1}
.own .reply{background:linear-gradient(135deg,#2DD4BF,#6366F1);color:#fff;font-size:12px;font-weight:600;
  border-radius:999px;padding:5px 9px;white-space:nowrap}
.own .sugg{flex:0 0 ${OWN_KEYBOARD.suggestionHeight}px;display:flex;align-items:center;padding:0 4px}
.own .sugg .cand{flex:1;text-align:center;font-size:17px;color:var(--label)}
.own .sugg .edge{width:44px;text-align:center;font-size:17px;color:var(--sub)}
.own .sugg .sep{width:1px;height:22px;background:rgba(60,60,67,.22)}
.own .panel{flex:1;background:var(--panel);display:flex;flex-direction:column}
.own .phdr{flex:0 0 38px;display:flex;align-items:center;gap:8px;padding:0 12px}
.own .phdr .chev{color:var(--sub);font-size:14px;font-weight:600;width:28px;text-align:center}
.own .phdr .mark{width:14px;height:14px;border-radius:3px;background:linear-gradient(135deg,#2DD4BF,#6366F1)}
.own .phdr .ttl{font-size:14px;font-weight:600;color:var(--label)}
.own .phdr .x{margin-left:auto;width:30px;height:30px;border-radius:50%;background:var(--fn);opacity:.6;
  display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:600;color:var(--sub)}
.own .load{padding:12px 16px 0;display:flex;flex-direction:column;gap:12px}
.own .shim{position:relative;height:11px;border-radius:4px;overflow:hidden}
.own .shim .base{position:absolute;inset:0;background:var(--txt2);opacity:.18}
.own .shim .glow{position:absolute;top:0;bottom:0;left:0;width:50%;
  background:linear-gradient(90deg,rgba(0,0,0,0),var(--txt1),rgba(0,0,0,0));opacity:.16}
`;

/** Our own keyboard with the AI result panel open and `AIResultPanel.loading`
 *  running, which is what is on screen for the whole five seconds of a read: the
 *  user tapped Reply on this thing.
 *
 *  It is here because the fingerprint has to be blind to it. The three shimmer
 *  lines repaint at `workingPhase += 0.03` every 16 ms, and the keyboard is a
 *  third of the fingerprint band, so a harness that only ever rendered a static
 *  system keyboard could not see the failure that cost a shipping build: every
 *  sampled frame got a new identity and the freshness gate retired the answer to
 *  the tap that paid for it. `phase` is `KeyboardController.workingPhase`. */
function ownKeyboard(spec) {
  const phase = spec.phase ?? 0;
  const rtl = spec.lang === "he";
  const line = (index, width) => {
    // `ShimmerLine`: a 50%-wide gradient offset by (phase * 1.6 - 0.4) * width,
    // with each of the three lines 0.18 further along than the one above it.
    const p = (phase + index * 0.18) % 1;
    const w = width ?? 370;
    const offset = (p * 1.6 - 0.4) * w;
    // `translateX` rather than `left`, because SwiftUI's `.offset(x:)` is a
    // draw-time transform and does not move the view's layout box. The
    // difference is not cosmetic here: `left` grows the panel's scrollable
    // overflow as the phase advances, and Chromium then rasterises a tile
    // boundary one pixel differently *above* the keyboard — a real difference in
    // the host's pixels caused by nothing but our own animation, which is the
    // one thing this variant must not manufacture.
    return (
      `<div class="shim" style="width:${w}px"><div class="base"></div>` +
      `<div class="glow" style="transform:translateX(${offset}px)"></div></div>`
    );
  };
  const cands = rtl ? ["אני", "תודה", "בסדר"] : ["I", "The", "Sure"];
  return `<div class="own ${spec.overlay ? "overlay" : ""}">
  <div class="strip"><div class="dot"></div>${ch(spec.sender ?? "Maya", "who")}` +
    `${ch(spec.said ?? "Reply can read this screen", "said")}${ch("Reply", "reply")}</div>
  <div class="sugg">${ch("☺", "edge")}<div class="sep"></div>` +
    cands.map((c) => ch(c, "cand")).join('<div class="sep"></div>') +
    `<div class="sep"></div>${ch("✦", "edge")}</div>
  <div class="panel">
    <div class="phdr">${ch("‹", "chev")}<div class="mark"></div>${ch("Reply", "ttl")}${ch("✕", "x")}</div>
    <div class="load">${line(0, 370)}${line(1, 220)}${line(2, 160)}</div>
  </div>
</div>`;
}

// ---------------------------------------------------------------------------
// Landscape
// ---------------------------------------------------------------------------

/** The same iPhone 17 Pro, rotated. `Theme.Metrics` is in points and
 *  `FrameReduction.Band.maximumOwnUI` is a *fraction*, so the short axis is the
 *  one the cap is spent against and it is the portrait width, not the height. */
export const LANDSCAPE_DEVICE = {
  name: "iPhone 17 Pro (landscape)",
  cssWidth: 874,
  cssHeight: 402,
  scale: 3,
  pixelWidth: 2622,
  pixelHeight: 1206,
};

/** `Theme.Metrics.Landscape`, in points, exactly as
 *  `totalHeight(for:showsBanner:orientation:)` adds them up: no banner at any
 *  `showsBanner`, a 30 pt suggestion bar, and a key area of three letter rows
 *  plus the bottom row at 26 pt with 8 pt gaps and portrait's own 4+4 insets.
 *
 *  26*4 + 8*3 + 8 = 136, and 0 + 30 + 136 = 166. `LandscapeGeometryTests`
 *  asserts both numbers; they are restated here rather than imported because
 *  this is JavaScript, and the harness prints them so a drift is visible in the
 *  output rather than buried. */
export const OWN_KEYBOARD_LANDSCAPE = {
  suggestionHeight: 30,
  keyHeight: 26,
  rowSpacing: 8,
  topInset: 4,
  bottomInset: 4,
  get keyAreaHeight() {
    return this.keyHeight * 4 + this.rowSpacing * 3 + this.topInset + this.bottomInset;
  },
  get totalHeight() {
    return this.suggestionHeight + this.keyAreaHeight;
  },
  /** `SuggestionBar.chipSize(for: .landscape)`. */
  chip: { width: 44, height: 26 },
  /** What `CaptureIntent.ownUIHeightPermille` carries on a screen this tall. */
  screenFraction(screenHeight = LANDSCAPE_DEVICE.cssHeight) {
    return this.totalHeight / screenHeight;
  },
};

/** The portrait shell, re-sized. Appended after every other block so it wins on
 *  source order at equal specificity.
 *
 *  **Three things here are approximations and they are named rather than
 *  hidden.** iOS hides the status bar on an iPhone in landscape, so it is
 *  collapsed rather than kept at its portrait 62 pt. The app nav bars keep their
 *  portrait heights, where a real landscape iPhone shortens them by about 12 pt
 *  — that pushes host content *down* toward the crop, so it is the conservative
 *  direction. And the host's own keyboard is re-sized to landscape metrics
 *  rather than re-drawn, because what the fingerprint sees of it is a dense
 *  patch of chrome either way. */
const LANDSCAPE_CSS = `
html,body{width:${LANDSCAPE_DEVICE.cssWidth}px;height:${LANDSCAPE_DEVICE.cssHeight}px}
.screen{width:${LANDSCAPE_DEVICE.cssWidth}px;height:${LANDSCAPE_DEVICE.cssHeight}px}
.island{display:none}
.statusbar{flex:0 0 0;height:0;padding:0;overflow:hidden}
.home-ind{bottom:5px;width:230px}
.kb{padding-bottom:12px}
.kb-sugg{height:30px}
.kb-sugg span{font-size:14px}
.kb-row{gap:6px;margin-bottom:8px}
.kb-key{width:74px;height:26px;font-size:18px}
.kb-key.wide{width:96px;font-size:13px}
.kb-key.space{width:360px;font-size:13px}
.kb-key.act{width:180px;font-size:13px}
`;

const OWN_LANDSCAPE_CSS = `
.ownl{--bg:#D1D3D9;--panel:#E6E8ED;--label:#000;--sub:#3C3C43;--txt1:#0B0B0F}
[data-appearance="dark"] .ownl{--bg:#161618;--panel:#2C2C2E;--label:#fff;--sub:#C7C7CC;--txt1:#F5F5F7}
.ownl{flex:0 0 auto;z-index:45;height:${OWN_KEYBOARD_LANDSCAPE.totalHeight}px;background:var(--bg);
  color:var(--label);display:flex;flex-direction:column;direction:ltr}
.ownl.overlay{position:absolute;left:0;right:0;bottom:0}
.ownl .lsugg{flex:0 0 ${OWN_KEYBOARD_LANDSCAPE.suggestionHeight}px;display:flex;align-items:center;padding:0 4px}
.ownl .lchip{width:${OWN_KEYBOARD_LANDSCAPE.chip.width}px;height:${OWN_KEYBOARD_LANDSCAPE.chip.height}px;
  border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:15px;color:var(--sub)}
.ownl .lsep{width:1px;height:18px;background:rgba(60,60,67,.22)}
.ownl .lcand{flex:1;text-align:center;font-size:15px;color:var(--label)}
.ownl .lreply{position:relative;width:${OWN_KEYBOARD_LANDSCAPE.chip.width}px;
  height:${OWN_KEYBOARD_LANDSCAPE.chip.height}px;border-radius:8px;overflow:hidden;
  background:linear-gradient(135deg,#EE7442,#D9632F);color:#fff;display:flex;align-items:center;
  justify-content:center;font-size:13px;font-weight:600}
.ownl .lsweep{position:absolute;top:0;bottom:0;left:0;border-radius:7px;background:rgba(255,255,255,.4)}
.ownl .lkeys{flex:1;padding:${OWN_KEYBOARD_LANDSCAPE.topInset}px 3px ${OWN_KEYBOARD_LANDSCAPE.bottomInset}px;
  display:flex;flex-direction:column;gap:${OWN_KEYBOARD_LANDSCAPE.rowSpacing}px}
.ownl .lrow{display:flex;justify-content:center;gap:6px;flex:0 0 ${OWN_KEYBOARD_LANDSCAPE.keyHeight}px}
.ownl .lkey{height:${OWN_KEYBOARD_LANDSCAPE.keyHeight}px;border-radius:5px;background:var(--panel);
  display:flex;align-items:center;justify-content:center;font-size:16px;color:var(--txt1)}
`;

/** Our own keyboard as landscape draws it, with a model call running.
 *
 *  **The moving part is a chip, not a banner, and that is the whole reason this
 *  render exists.** Landscape shows no `ActionBanner` at any `showsBanner`, so
 *  the three shimmer lines the portrait variant was built around are not on
 *  screen at all. What is on screen for the whole of a read is
 *  `ControlSweep`: a capsule of `segmentFraction` (0.32) of the chip's width,
 *  white at `fillOpacity` (0.4), clipped to the chip and offset by
 *  `phase % 1 * (width + segment) - segment`. It rides the Reply chip, which
 *  ships on `barTrailing` and is what `KeyActivity.resolve` lights during a
 *  screen read.
 *
 *  The action row is shed in landscape, so its five controls are chips on this
 *  bar — `SuggestionBar.landscapeActions(for:)`, in the order
 *  `LandscapeGeometryTests` pins: CopyClip, Fix, Emoji, Rewrite, dictation. */
function ownKeyboardLandscape(spec) {
  const phase = spec.phase ?? 0;
  const lang = spec.lang === "he" ? "he" : "en";
  const chip = OWN_KEYBOARD_LANDSCAPE.chip;
  const segment = chip.width * 0.32;
  const offset = ((phase % 1) + 1) % 1 * (chip.width + segment) - segment;

  const strip = ["\u{1F4CB}", "✦", "☺", "✨", "\u{1F3A4}"]
    .map((g) => `<div class="lchip">${ch(g)}</div>`)
    .join("");
  const cands = (lang === "he" ? ["אני", "תודה", "בסדר"] : ["I", "The", "Sure"])
    .map((c) => ch(c, "lcand"))
    .join("");
  const reply =
    `<div class="lreply">${ch("Reply")}` +
    `<div class="lsweep" style="width:${segment}px;transform:translateX(${offset}px)"></div></div>`;

  const rows = KB_ROWS[lang];
  const key = (c, width) => `<div class="lkey" style="width:${width}px">${ch(c)}</div>`;
  // Ten reference columns across 874 pt less the 3 pt side inset each side and
  // nine 6 pt gutters, which is `KeyWidth`'s own arithmetic at this width.
  const unit = (LANDSCAPE_DEVICE.cssWidth - 6 - 9 * 6) / 10;
  const shift = lang === "he" ? "" : "⇧";
  const keys = [
    `<div class="lrow">${rows[0].map((c) => key(c, unit)).join("")}</div>`,
    `<div class="lrow">${rows[1].map((c) => key(c, unit)).join("")}</div>`,
    `<div class="lrow">${key(shift || "", unit * 1.5)}` +
      rows[2].map((c) => key(c, unit)).join("") +
      `${key("⌫", unit * 1.5)}</div>`,
    `<div class="lrow">${key("123", unit * 1.25)}${key("⚙", unit)}` +
      `${key(lang === "he" ? "רווח" : "space", unit * 4.5)}${key(".", unit)}` +
      `${key(lang === "he" ? "שורה" : "return", unit * 1.5)}</div>`,
  ].join("");

  return `<div class="ownl ${spec.overlay ? "overlay" : ""}">
  <div class="lsugg">${strip}<div class="lsep"></div>${cands}<div class="lsep"></div>${reply}</div>
  <div class="lkeys">${keys}</div>
</div>`;
}

/** One scene, rendered on a rotated screen.
 *
 *  The same `render` the corpus uses, with the shell re-sized by a stylesheet
 *  appended after every other block. It is the portrait skins relaid, not a
 *  photograph of a real app in landscape: the bubbles are percentage-width so
 *  they widen and fewer of them fit, which is the shape that matters here, but
 *  no real app's landscape-specific chrome is reproduced. Say so beside any
 *  number taken from it. */
export function renderLandscape(scene, screenHeight = LANDSCAPE_DEVICE.cssHeight) {
  const html = render(scene);
  // The short axis is the whole question: the cap is a fraction of it and our
  // keyboard is 166 points of it whatever it measures, so the harness renders
  // the same scene at each shipping phone's landscape height.
  const height = `\nhtml,body{height:${screenHeight}px}\n.screen{height:${screenHeight}px}\n`;
  const injected = `${OWN_LANDSCAPE_CSS}${LANDSCAPE_CSS}${height}</style>`;
  if (!html.includes("</style>")) throw new Error("the page shell has no <style> to extend");
  return html.replace("</style>", injected);
}

/** The iOS keyboard. Forty-odd single letters an inch from the message text —
 *  the densest patch of chrome on any of these screens. */
function keyboard(spec) {
  if (!spec) return "";
  if (spec.ours) return spec.landscape ? ownKeyboardLandscape(spec) : ownKeyboard(spec);
  const lang = spec.lang ?? "en";
  const rows = KB_ROWS[lang];
  const key = (c, cls = "") => `<div class="kb-key ${cls}">${ch(c)}</div>`;
  const shift = lang === "he" ? "" : "⇧";
  const rowHtml = [
    `<div class="kb-row">${rows[0].map((c) => key(c)).join("")}</div>`,
    `<div class="kb-row">${rows[1].map((c) => key(c)).join("")}</div>`,
    `<div class="kb-row">${shift ? key(shift, "wide") : `<div class="kb-key wide"></div>`}` +
      rows[2].map((c) => key(c)).join("") +
      `${key("⌫", "wide")}</div>`,
    `<div class="kb-row">${key("123", "wide")}${key("🌐", "wide")}` +
      `${key(lang === "he" ? "רווח" : "space", "space")}` +
      `${key(lang === "he" ? "שורה" : "return", "act")}</div>`,
  ].join("");
  const sugg = KB_SUGGESTIONS[lang].map((s) => ch(s)).join("");
  return `<div class="kb ${spec.overlay ? "overlay" : ""}">
    <div class="kb-sugg">${sugg}</div>${rowHtml}</div>`;
}

// ---------------------------------------------------------------------------
// WhatsApp
// ---------------------------------------------------------------------------

// WhatsApp's doodle wallpaper. It matters because it puts thin dark strokes
// directly behind the white bubbles, which is where a naive binarisation
// threshold goes wrong. Kept faint, the way the real one is.
const DOODLE = encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><g fill="none" stroke="#000" stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round">` +
    `<path d="M9 14c3-4 8-4 11 0M30 9h9v7h-5l-2 3-1-3h-1zM52 12l4-4 4 4-4 4zM72 7v9M68 11h9M88 15a5 5 0 1 0 .1 0M104 8h10v8h-10zM118 20l5 5"/>` +
    `<path d="M6 36a6 6 0 1 0 .1 0M22 44l5 9H17zM38 38h11v8h-6l-2 3-1-3h-2zM60 34v8M56 38h8M76 40l5-5 5 5-5 5zM96 36h8M100 32v8M114 34a7 7 0 1 0 .1 0"/>` +
    `<path d="M10 66h9v7h-9zM32 62l6 11H26zM50 68a5 5 0 1 0 .1 0M66 60h11v8h-6l-2 3-1-3h-2zM88 64l4-4 4 4-4 4zM104 60v9M100 64h9M118 66h6v7h-6z"/>` +
    `<path d="M8 92h10M13 88l4 4-4 4M28 88a6 6 0 1 0 .1 0M44 90h10v8h-6l-2 3-1-3h-1zM64 86l5 5-5 5-5-5zM82 96l5-9 5 9zM100 88h9v8h-9zM120 90v8"/>` +
    `<path d="M6 114c3-4 8-4 11 0M26 112h9v7h-5l-2 3-1-3h-1zM48 110a6 6 0 1 0 .1 0M64 116h9M68 112v8M84 112l4-4 4 4-4 4zM102 108l6 11H96zM120 112h6v7h-6z"/>` +
    `</g></svg>`
);

const WA_CSS = `
.wa{--nav:#F6F6F6;--navtxt:#000;--tint:#007AFF;--bg:#EFEAE2;--in:#FFFFFF;--out:#D9FDD3;
  --txt:#111B21;--meta:#667781;--sub:#667781;--sep:#D4D4D8;--chip:#FFFFFF;--chiptxt:#54656F;
  --enc:#FFF3C7;--enctxt:#7D6A2A;--doodle:.055;--comp:#FFFFFF;--compbg:#F6F6F6;--home:#000}
.wa[data-appearance="dark"]{--nav:#1F2C34;--navtxt:#E9EDEF;--tint:#00A884;--bg:#0B141A;--in:#202C33;
  --out:#005C4B;--txt:#E9EDEF;--meta:#8696A0;--sub:#8696A0;--sep:#222D34;--chip:#182229;--chiptxt:#8696A0;
  --enc:#182229;--enctxt:#FFD279;--doodle:.035;--comp:#2A3942;--compbg:#0B141A;--home:#fff}
.wa{background:var(--bg);color:var(--txt)}
.wa .statusbar{background:var(--nav);color:var(--navtxt)}
.wa .home-ind{background:var(--home)}
.wa .nav{flex:0 0 44px;background:var(--nav);color:var(--navtxt);display:flex;align-items:center;
  gap:8px;padding:0 12px 0 6px;border-bottom:.5px solid var(--sep)}
.wa .nav .back{color:var(--tint);display:flex;align-items:center;padding:0 2px}
.wa .nav .av{width:33px;height:33px;border-radius:50%;flex:0 0 33px;
  background:linear-gradient(150deg,#7E9AA8,#4B6572);display:flex;align-items:center;justify-content:center;
  color:#fff;font-size:14px;font-weight:500}
.wa .nav .who{flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center}
.wa .nav .name{font-size:16px;font-weight:600;letter-spacing:-.2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.wa .nav .pres{font-size:12px;color:var(--sub);margin-top:1px}
.wa .nav .ico{color:var(--tint);display:flex;align-items:center}
.wa .thread{background-color:var(--bg);position:relative}
.wa .thread::before{content:"";position:absolute;inset:0;pointer-events:none;
  background-image:url("data:image/svg+xml,${DOODLE}");background-size:128px 128px;opacity:var(--doodle)}
.wa[data-appearance="dark"] .thread::before{filter:invert(1)}
.wa .thread-inner{padding:8px 8px 6px;gap:2px;position:relative}
.wa .chip{align-self:center;background:var(--chip);color:var(--chiptxt);font-size:12.5px;font-weight:500;
  padding:5px 12px;border-radius:7px;margin:6px 0;box-shadow:0 1px .5px rgba(11,20,26,.13)}
.wa .enc{align-self:center;background:var(--enc);color:var(--enctxt);font-size:12.5px;line-height:1.35;
  padding:6px 12px;border-radius:7px;margin:2px 0 8px;max-width:88%;text-align:center}
.wa .row{display:flex;margin-bottom:2px}
.wa .row.them{justify-content:flex-start}
.wa .row.me{justify-content:flex-end}
.wa .bub{position:relative;max-width:78%;border-radius:7.5px;padding:6px 9px 8px;
  box-shadow:0 1px .5px rgba(11,20,26,.13);font-size:16.3px;line-height:1.32}
.wa .row.them .bub{background:var(--in);border-top-left-radius:0}
.wa .row.me .bub{background:var(--out);border-top-right-radius:0}
.wa[dir="rtl"] .row.them .bub{border-top-left-radius:7.5px;border-top-right-radius:0}
.wa[dir="rtl"] .row.me .bub{border-top-right-radius:7.5px;border-top-left-radius:0}
.wa .who-in{display:block;font-size:12.8px;font-weight:500;margin-bottom:1px}
.wa .meta{float:right;font-size:11px;color:var(--meta);margin:6px 0 -3px 8px;
  display:inline-flex;align-items:center;gap:3px;white-space:nowrap}
.wa .bub[dir="rtl"] .meta{float:left;margin:6px 8px -3px 0}
.wa .tick{color:#53BDEB;font-size:12px}
.wa .quote{border-left:3.5px solid var(--tint);background:rgba(0,0,0,.05);border-radius:5px;
  padding:4px 8px;margin-bottom:3px;display:flex;flex-direction:column;gap:1px}
.wa[data-appearance="dark"] .quote{background:rgba(255,255,255,.06)}
.wa .bub[dir="rtl"] .quote{border-left:none;border-right:3.5px solid var(--tint)}
.wa .quote .qn{font-size:12.8px;font-weight:500;color:var(--tint)}
.wa .quote .qt{font-size:13.5px;color:var(--meta);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.wa .react{position:absolute;bottom:-11px;background:var(--in);border:1.5px solid var(--bg);
  border-radius:11px;padding:1px 6px;font-size:12px;display:flex;gap:3px;align-items:center;
  box-shadow:0 1px 2px rgba(11,20,26,.15);color:var(--meta)}
.wa .row.them .react{left:8px}
.wa .row.me .react{right:8px}
.wa .spacer{height:12px}
.wa .voice{display:flex;align-items:center;gap:8px;min-width:200px}
.wa .voice .play{font-size:20px;color:var(--meta)}
.wa .voice .wave{flex:1;height:22px;display:flex;align-items:center;gap:2px}
.wa .voice .wave i{flex:1;background:var(--meta);opacity:.45;border-radius:1px}
.wa .typing{font-size:12px;color:var(--sub)}
.wa .comp{flex:0 0 auto;background:var(--compbg);padding:7px 8px 8px;display:flex;align-items:flex-end;
  gap:8px;border-top:.5px solid var(--sep)}
.wa .comp .field{flex:1;background:var(--comp);border-radius:19px;padding:9px 12px;font-size:16px;
  color:var(--meta);display:flex;align-items:center;gap:10px;box-shadow:0 1px .5px rgba(11,20,26,.1)}
.wa .comp .btn{width:37px;height:37px;border-radius:50%;background:var(--tint);color:#fff;
  display:flex;align-items:center;justify-content:center;font-size:17px;flex:0 0 37px}
.wa .kb{background:${"#D1D3D9"}}
.wa[data-appearance="dark"] .kb{background:#2C2C2E}
`;

const KB_CSS = `
.kb{background:#D1D3D9;color:#000}
.kb .kb-key{background:#fff;box-shadow:0 1px 0 rgba(0,0,0,.28)}
.kb .kb-key.wide,.kb .kb-key.act{background:#AEB3BE}
.kb .kb-sugg span{color:#000}
[data-appearance="dark"] .kb{background:#2C2C2E;color:#fff}
[data-appearance="dark"] .kb .kb-key{background:#6C6C70;box-shadow:0 1px 0 rgba(0,0,0,.5)}
[data-appearance="dark"] .kb .kb-key.wide,[data-appearance="dark"] .kb .kb-key.act{background:#4A4A4E}
[data-appearance="dark"] .kb .kb-sugg span{color:#fff}
`;

function waTicks(status) {
  if (!status) return "";
  const cls = status === "read" ? "tick" : "";
  return `<span class="${cls}">✓✓</span>`;
}

function renderWhatsApp(s) {
  const rtl = s.dir === "rtl";
  const initials = (s.header.title.match(/\S/g) ?? ["?"])[0];
  const rows = s.messages
    .map((m, i) => {
      const id = `m${i}`;
      if (m.kind === "date") return `<div class="chip">${ch(m.text)}</div>`;
      if (m.kind === "system") return `<div class="enc">${ch(m.text)}</div>`;
      if (m.kind === "typing")
        return `<div class="row them"><div class="bub">${ch(m.text, "typing")}</div></div>`;
      const inner = [];
      if (m.quoted)
        inner.push(
          `<div class="quote">${ch(m.quoted.name, "qn")}${ch(m.quoted.text, "qt")}</div>`
        );
      if (m.senderLabel) inner.push(ch(m.senderLabel, "who-in"));
      if (m.kind === "voice") {
        inner.push(
          `<div class="voice"><span class="play">${ICON.play}</span><div class="wave">` +
            Array.from({ length: 26 }, (_, k) => `<i style="height:${4 + ((k * 7) % 17)}px"></i>`).join("") +
            `</div>${ch(m.duration ?? "0:14")}</div>`
        );
      } else {
        inner.push(body(m, id, m.text));
      }
      inner.push(`<span class="meta">${ch(m.time)}${waTicks(m.status)}</span>`);
      const react = m.reactions
        ? `<div class="react" dir="ltr">${m.reactions.map((r) => ch(r)).join("")}</div>`
        : "";
      // Bubbles carry their own text direction: a Hebrew message stays
      // right-aligned even when the phone's UI language leaves the app in LTR.
      const bdir = hasHebrew(m.text) || hasHebrew(m.quoted?.text ?? "") ? "rtl" : "ltr";
      return `<div class="row ${m.from}"><div class="bub" dir="${bdir}">${inner.join("")}${react}</div></div>` +
        (m.reactions ? `<div class="spacer"></div>` : "");
    })
    .join("");

  return page(s, WA_CSS, "wa", [
    statusBar(s.statusTime),
    `<div class="nav"><span class="back">${ICON.chev}</span><div class="av">${ch(initials)}</div>` +
      `<div class="who">${ch(s.header.title, "name")}${ch(s.header.subtitle, "pres")}</div>` +
      `<span class="ico">${ICON.video}</span><span class="ico">${ICON.phone}</span></div>`,
    `<div class="thread" dir="${rtl ? "rtl" : "ltr"}"><div class="thread-inner">${rows}</div></div>`,
    `<div class="comp" dir="${rtl ? "rtl" : "ltr"}"><div class="field">${ICON.plus}` +
      `${ch(rtl ? "הודעה" : "Message")}${ICON.camera}</div><div class="btn">${ICON.mic}</div></div>`,
    keyboard(s.keyboard),
    homeIndicator(),
  ]);
}

// ---------------------------------------------------------------------------
// Slack
// ---------------------------------------------------------------------------

const SLACK_CSS = `
.sl{--bg:#FFFFFF;--nav:#FFFFFF;--txt:#1D1C1D;--meta:#616061;--sep:#E8E8E8;--link:#1264A3;
  --divider:#E01E5A;--pill:#F8F8F8;--pillb:#DDDDDD;--code:#F3F3F3;--codetxt:#E01E5A;--home:#000;
  --comp:#FFFFFF;--compb:#BEBEBE;--hdr:#3F0E40}
.sl[data-appearance="dark"]{--bg:#1A1D21;--nav:#1A1D21;--txt:#D1D2D3;--meta:#ABABAD;--sep:#35373B;
  --link:#1D9BD1;--divider:#E01E5A;--pill:#22252A;--pillb:#35373B;--code:#232529;--codetxt:#E06C75;
  --home:#fff;--comp:#222529;--compb:#4A4C50;--hdr:#1A1D21}
.sl{background:var(--bg);color:var(--txt);font-size:15px}
.sl .statusbar{background:var(--nav);color:var(--txt)}
.sl .home-ind{background:var(--home)}
.sl .nav{flex:0 0 46px;background:var(--nav);display:flex;align-items:center;gap:10px;padding:0 14px;
  border-bottom:1px solid var(--sep)}
.sl .nav .back{color:var(--txt);display:flex;align-items:center}
.sl .comp .tools{display:flex;gap:14px;color:var(--meta)}
.sl .nav .who{flex:1;min-width:0}
.sl .nav .name{display:block;font-size:15.5px;font-weight:700;letter-spacing:-.1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sl .nav .sub{display:block;font-size:12px;color:var(--meta);margin-top:1px}
.sl .thread-inner{padding:6px 0 10px}
.sl .day{display:flex;align-items:center;gap:10px;padding:10px 16px 6px}
.sl .day .line{flex:1;height:1px;background:var(--sep)}
.sl .day .lbl{border:1px solid var(--sep);border-radius:14px;padding:3px 12px;font-size:12.5px;font-weight:700}
.sl .new{display:flex;align-items:center;gap:8px;padding:8px 16px 2px}
.sl .new .line{flex:1;height:1px;background:var(--divider)}
.sl .new .lbl{color:var(--divider);font-size:12px;font-weight:700}
.sl .post{display:flex;gap:9px;padding:7px 16px 6px}
.sl .post.cont{padding-top:1px}
.sl .av{width:36px;height:36px;flex:0 0 36px;border-radius:8px;display:flex;align-items:center;
  justify-content:center;color:#fff;font-size:15px;font-weight:600}
.sl .av.ghost{background:none}
.sl .col{flex:1;min-width:0}
.sl .hdr{display:flex;align-items:baseline;gap:7px;margin-bottom:1px;flex-wrap:wrap}
.sl .hdr .nm{font-size:15px;font-weight:700;letter-spacing:-.1px}
.sl .hdr .tag{font-size:10px;font-weight:700;background:var(--pillb);color:var(--meta);
  border-radius:2px;padding:1px 4px;text-transform:uppercase}
.sl .hdr .tm{font-size:12px;color:var(--meta)}
.sl .txt{font-size:15px;line-height:1.46}
.sl .link{color:var(--link)}
.sl .reacts{display:flex;gap:6px;margin-top:6px;flex-wrap:wrap}
.sl .reacts .r{border:1px solid var(--pillb);background:var(--pill);border-radius:12px;
  padding:2px 8px;font-size:12.5px;display:flex;gap:4px;align-items:center}
.sl .replies{margin-top:5px;font-size:13px;color:var(--link);font-weight:600}
.sl .card{margin-top:7px;border-left:4px solid var(--pillb);padding-left:10px;display:flex;
  flex-direction:column;gap:2px}
.sl .card .ct{font-size:14.5px;font-weight:700;color:var(--link)}
.sl .card .cd{font-size:14px;color:var(--meta);line-height:1.4}
.sl .card .ch{font-size:12px;color:var(--meta)}
.sl .comp{flex:0 0 auto;padding:8px 12px 10px;background:var(--bg);border-top:1px solid var(--sep)}
.sl .comp .box{border:1px solid var(--compb);border-radius:8px;background:var(--comp);padding:11px 12px;
  font-size:15px;color:var(--meta);display:flex;justify-content:space-between}
`;

const SL_AV = ["#4A154B", "#2EB67D", "#ECB22E", "#E01E5A", "#36C5F0", "#616061"];

function renderSlack(s) {
  const rtl = s.dir === "rtl";
  let avIdx = 0;
  const seen = new Map();
  const avatarFor = (name) => {
    if (!seen.has(name)) seen.set(name, SL_AV[avIdx++ % SL_AV.length]);
    return seen.get(name);
  };
  const rows = s.messages
    .map((m, i) => {
      const id = `m${i}`;
      if (m.kind === "date")
        return `<div class="day"><div class="line"></div>${ch(m.text, "lbl")}<div class="line"></div></div>`;
      if (m.kind === "unread")
        return `<div class="new"><div class="line"></div>${ch(m.text, "lbl")}</div>`;
      const nm = m.senderLabel ?? m.sender;
      const hdr = m.cont
        ? ""
        : `<div class="hdr">${ch(nm, "nm")}${m.appTag ? ch("App", "tag") : ""}${ch(m.time, "tm")}</div>`;
      const av = m.cont
        ? `<div class="av ghost"></div>`
        : `<div class="av" style="background:${avatarFor(nm)}">${ch((nm.match(/\S/g) ?? ["?"])[0])}</div>`;
      const parts = [hdr];
      parts.push(`<div dir="${hasHebrew(m.text) ? "rtl" : "ltr"}">${body(m, id, m.text)}</div>`);
      if (m.card)
        parts.push(
          `<div class="card">${ch(m.card.title, "ct")}${ch(m.card.desc, "cd")}${ch(m.card.host, "ch")}</div>`
        );
      if (m.reactions)
        parts.push(`<div class="reacts">${m.reactions.map((r) => ch(r, "r")).join("")}</div>`);
      if (m.replies) parts.push(ch(m.replies, "replies"));
      return `<div class="post ${m.cont ? "cont" : ""}">${av}<div class="col">${parts.join("")}</div></div>`;
    })
    .join("");

  return page(s, SLACK_CSS, "sl", [
    statusBar(s.statusTime),
    `<div class="nav"><span class="back">${ICON.chev}</span><div class="who">${ch(s.header.title, "name")}` +
      `${ch(s.header.subtitle, "sub")}</div>${ICON.menu}</div>`,
    `<div class="thread" dir="${rtl ? "rtl" : "ltr"}"><div class="thread-inner">${rows}</div></div>`,
    `<div class="comp"><div class="box">${ch(s.composer ?? "Message")}` +
      `<span class="tools">${ICON.plus}${ICON.smiley}${ICON.at}</span></div></div>`,
    keyboard(s.keyboard),
    homeIndicator(),
  ]);
}

// ---------------------------------------------------------------------------
// Messages (iMessage)
// ---------------------------------------------------------------------------

const IM_CSS = `
.im{--bg:#FFFFFF;--nav:#F9F9F9;--txt:#000000;--in:#E9E9EB;--intxt:#000;--out:#248BF5;--outtxt:#fff;
  --meta:#8E8E93;--sep:#D1D1D6;--tint:#007AFF;--home:#000;--comp:#FFFFFF;--compb:#C7C7CC;--card:#F2F2F7}
.im[data-appearance="dark"]{--bg:#000000;--nav:#1C1C1E;--txt:#FFFFFF;--in:#262628;--intxt:#fff;
  --out:#0B84FF;--outtxt:#fff;--meta:#8E8E93;--sep:#38383A;--tint:#0A84FF;--home:#fff;--comp:#1C1C1E;
  --compb:#3A3A3C;--card:#1C1C1E}
.im{background:var(--bg);color:var(--txt)}
.im .statusbar{background:var(--nav);color:var(--txt)}
.im .home-ind{background:var(--home)}
.im .nav{flex:0 0 54px;background:var(--nav);display:flex;align-items:center;padding:0 12px 4px;
  border-bottom:.5px solid var(--sep);position:relative}
.im .nav .back{color:var(--tint);display:flex;align-items:center;margin-bottom:2px}
.im .nav .badge{color:var(--tint);font-size:15px;margin:0 2px 2px;z-index:1}
.im .nav .center{position:absolute;left:0;right:0;display:flex;flex-direction:column;align-items:center;gap:2px}
.im .nav .av{width:30px;height:30px;border-radius:50%;background:linear-gradient(160deg,#B0B3B8,#7C8085);
  display:flex;align-items:center;justify-content:center;color:#fff;font-size:13px;font-weight:500}
.im .nav .nm{font-size:11.5px;letter-spacing:-.1px}
.im .nav .ico{margin-inline-start:auto;color:var(--tint);display:flex;align-items:center;margin-bottom:2px;z-index:1}
.im .thread-inner{padding:6px 14px 8px;gap:2px}
.im .stamp{align-self:center;font-size:11.5px;color:var(--meta);margin:10px 0 6px;text-align:center}
.im .stamp b{font-weight:600;color:var(--txt);opacity:.75}
.im .row{display:flex;margin-bottom:2px}
.im .row.them{justify-content:flex-start}
.im .row.me{justify-content:flex-end}
.im .row.tapped{margin-top:15px}
.im .bub{position:relative;max-width:76%;border-radius:18px;padding:8px 13px 9px;
  font-size:17px;line-height:1.29;letter-spacing:-.25px}
.im .row.them .bub{background:var(--in);color:var(--intxt);border-bottom-left-radius:5px}
.im .row.me .bub{background:var(--out);color:var(--outtxt);border-bottom-right-radius:5px}
.im[dir="rtl"] .row.them .bub{border-bottom-left-radius:18px;border-bottom-right-radius:5px}
.im[dir="rtl"] .row.me .bub{border-bottom-right-radius:18px;border-bottom-left-radius:5px}
.im .tap{position:absolute;top:-14px;background:var(--in);border:2px solid var(--bg);border-radius:14px;
  min-width:28px;height:26px;display:flex;align-items:center;justify-content:center;gap:2px;
  font-size:12.5px;padding:0 6px;color:var(--txt)}
.im .row.them .tap{right:-10px}
.im .row.me .tap{left:-10px}
/* flex-end on the cross axis follows the writing direction, so the receipt sits
   under the outgoing bubble in both layouts without an RTL override. */
.im .status{align-self:flex-end;font-size:11px;color:var(--meta);margin:1px 4px 4px}
.im .sname{font-size:11.5px;color:var(--meta);margin:4px 0 1px;margin-inline-start:14px}
.im .card{max-width:72%;border-radius:16px;overflow:hidden;background:var(--card);border:.5px solid var(--sep)}
.im .card .img{height:96px;background:linear-gradient(135deg,#5B8DEF,#2D5FC4)}
.im .card .body{padding:8px 11px 10px;display:flex;flex-direction:column;gap:2px}
.im .card .ct{font-size:14px;font-weight:600;line-height:1.3}
.im .card .ch{font-size:12px;color:var(--meta)}
.im .photo{width:186px;height:140px;border-radius:16px;
  background:linear-gradient(150deg,#F0C27B,#C06C4B 55%,#4B1248);display:flex;align-items:flex-end;padding:8px}
.im .comp{flex:0 0 auto;background:var(--nav);padding:8px 12px 10px;display:flex;align-items:center;gap:10px;
  border-top:.5px solid var(--sep)}
.im .comp .plus{color:var(--meta);display:flex;align-items:center}
.im .comp .field{flex:1;border:1px solid var(--compb);background:var(--comp);border-radius:18px;
  padding:8px 12px;font-size:17px;color:var(--meta);display:flex;justify-content:space-between;align-items:center}
.im .comp .send{width:28px;height:28px;border-radius:50%;background:var(--tint);color:#fff;
  display:flex;align-items:center;justify-content:center;font-size:15px}
`;

function renderIMessage(s) {
  const rtl = s.dir === "rtl";
  // Messages shows the receipt under the newest outgoing bubble only.
  const lastOut = s.messages.map((m) => Boolean(m.from === "me" && m.status)).lastIndexOf(true);
  const rows = s.messages
    .map((m, i) => {
      const id = `m${i}`;
      if (m.kind === "date") return `<div class="stamp">${ch(m.text)}</div>`;
      if (m.kind === "unread") return `<div class="stamp">${ch(m.text)}</div>`;
      const tap = m.reactions
        ? `<div class="tap" dir="ltr">${m.reactions.map((r) => ch(r)).join("")}</div>`
        : "";
      const bdir = hasHebrew(m.text) ? "rtl" : "ltr";
      let content;
      if (m.kind === "image") {
        content = `<div class="row ${m.from}"><div class="photo">${ch(m.imageLabel ?? "")}</div></div>`;
      } else if (m.card) {
        content =
          `<div class="row ${m.from}"><div class="card"><div class="img"></div>` +
          `<div class="body">${ch(m.card.title, "ct")}${ch(m.card.host, "ch")}</div></div></div>`;
      } else {
        content =
          `<div class="row ${m.from} ${m.reactions ? "tapped" : ""}">` +
          `<div class="bub" dir="${bdir}">${body(m, id, m.text)}${tap}</div></div>`;
      }
      const label = m.senderLabel ? `<div class="sname">${ch(m.senderLabel)}</div>` : "";
      const st = i === lastOut ? `<div class="status">${ch(m.status)}</div>` : "";
      return label + content + st;
    })
    .join("");

  return page(s, IM_CSS, "im", [
    statusBar(s.statusTime),
    `<div class="nav"><span class="back">${ICON.chev}</span>${ch(s.header.badge ?? "", "badge")}` +
      `<div class="center"><div class="av">${ch((s.header.title.match(/\S/g) ?? ["?"])[0])}</div>` +
      `${ch(s.header.title, "nm")}</div><span class="ico">${ICON.video}</span></div>`,
    `<div class="thread" dir="${rtl ? "rtl" : "ltr"}"><div class="thread-inner">${rows}</div></div>`,
    `<div class="comp" dir="${rtl ? "rtl" : "ltr"}"><span class="plus">${ICON.plus}</span>` +
      `<div class="field">${ch(s.composer ?? "iMessage")}${ICON.smiley}</div>` +
      `<div class="send">${ICON.send}</div></div>`,
    keyboard(s.keyboard),
    homeIndicator(),
  ]);
}

// ---------------------------------------------------------------------------
// Telegram
// ---------------------------------------------------------------------------

const TG_CSS = `
.tg{--bg1:#DFE7F0;--bg2:#C7D6E6;--nav:#F7F7F8;--txt:#000;--in:#FFFFFF;--out:#EEFFDE;--meta:#6D7883;
  --outmeta:#5EBE6E;--sep:#C8C7CC;--tint:#3390EC;--home:#000;--comp:#FFFFFF;--pill:rgba(255,255,255,.85)}
.tg[data-appearance="dark"]{--bg1:#12181F;--bg2:#0E1621;--nav:#17212B;--txt:#FFFFFF;--in:#182533;
  --out:#2B5278;--meta:#7D8B99;--outmeta:#79C8F5;--sep:#101921;--tint:#5EA9DD;--home:#fff;
  --comp:#17212B;--pill:rgba(24,37,51,.9)}
.tg{background:linear-gradient(160deg,var(--bg1),var(--bg2));color:var(--txt)}
.tg .statusbar{background:var(--nav);color:var(--txt)}
.tg .home-ind{background:var(--home)}
.tg .nav{flex:0 0 46px;background:var(--nav);display:flex;align-items:center;gap:8px;padding:0 12px;
  border-bottom:.5px solid var(--sep);position:relative}
.tg .nav .back{color:var(--tint);font-size:16px;display:flex;align-items:center;gap:3px;z-index:1}
.tg .nav .center{position:absolute;left:64px;right:64px;display:flex;flex-direction:column;align-items:center}
.tg .nav .nm{font-size:16px;font-weight:600;letter-spacing:-.2px}
.tg .nav .sub{font-size:12.5px;color:var(--meta);margin-top:1px}
.tg .nav .av{margin-left:auto;z-index:1;width:33px;height:33px;border-radius:50%;
  background:linear-gradient(150deg,#9DB4CE,#5B7C9E);display:flex;align-items:center;justify-content:center;
  color:#fff;font-size:14px;font-weight:500}
.tg .thread-inner{padding:6px 10px 8px;gap:3px}
.tg .chip{align-self:center;background:var(--pill);color:var(--meta);font-size:12.5px;font-weight:500;
  padding:4px 12px;border-radius:12px;margin:5px 0}
.tg[data-appearance="dark"] .chip{color:#fff}
.tg .row{display:flex;margin-bottom:1px}
.tg .row.them{justify-content:flex-start}
.tg .row.me{justify-content:flex-end}
.tg .bub{position:relative;max-width:78%;border-radius:13px;padding:6px 10px 7px;font-size:16.5px;
  line-height:1.31;box-shadow:0 1px 1px rgba(16,35,47,.1)}
.tg .row.them .bub{background:var(--in);border-bottom-left-radius:4px}
.tg .row.me .bub{background:var(--out);border-bottom-right-radius:4px}
.tg[dir="rtl"] .row.them .bub{border-bottom-left-radius:13px;border-bottom-right-radius:4px}
.tg[dir="rtl"] .row.me .bub{border-bottom-right-radius:13px;border-bottom-left-radius:4px}
.tg .fwd{display:block;font-size:13.5px;color:var(--tint);margin-bottom:2px}
.tg .who-in{display:block;font-size:14px;font-weight:600;color:var(--tint);margin-bottom:1px}
.tg .quote{border-left:2px solid var(--tint);padding-left:8px;margin-bottom:4px;display:flex;
  flex-direction:column;gap:0}
.tg .bub[dir="rtl"] .quote{border-left:none;border-right:2px solid var(--tint);padding-left:0;padding-right:8px}
.tg .quote .qn{font-size:13.5px;font-weight:600;color:var(--tint)}
.tg .quote .qt{font-size:13.5px;color:var(--meta);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
  max-width:220px}
.tg .meta{float:right;font-size:11.5px;color:var(--meta);margin:7px 0 -2px 7px;white-space:nowrap}
.tg .row.me .meta{color:var(--outmeta)}
.tg .bub[dir="rtl"] .meta{float:left;margin:7px 7px -2px 0}
.tg .react{display:inline-flex;gap:4px;align-items:center;background:rgba(51,144,236,.14);color:var(--tint);
  border-radius:11px;padding:2px 8px;font-size:12.5px;margin-top:5px}
.tg .comp{flex:0 0 auto;background:var(--comp);padding:7px 10px 9px;display:flex;align-items:center;gap:10px;
  border-top:.5px solid var(--sep)}
.tg .comp .field{flex:1;font-size:16.5px;color:var(--meta);display:flex;justify-content:space-between}
.tg .comp .ico{color:var(--meta);display:flex;align-items:center}
`;

function renderTelegram(s) {
  const rtl = s.dir === "rtl";
  const rows = s.messages
    .map((m, i) => {
      const id = `m${i}`;
      if (m.kind === "date") return `<div class="chip">${ch(m.text)}</div>`;
      if (m.kind === "system") return `<div class="chip">${ch(m.text)}</div>`;
      const inner = [];
      if (m.forwarded) inner.push(ch(m.forwarded, "fwd"));
      if (m.quoted)
        inner.push(`<div class="quote">${ch(m.quoted.name, "qn")}${ch(m.quoted.text, "qt")}</div>`);
      if (m.senderLabel) inner.push(ch(m.senderLabel, "who-in"));
      inner.push(body(m, id, m.text));
      inner.push(`<span class="meta">${ch(m.time + (m.status === "read" ? " ✓✓" : m.status === "sent" ? " ✓" : ""))}</span>`);
      const react = m.reactions
        ? `<div style="display:flex" dir="ltr">${m.reactions.map((r) => ch(r, "react")).join("")}</div>`
        : "";
      const bdir = hasHebrew(m.text) || hasHebrew(m.quoted?.text ?? "") ? "rtl" : "ltr";
      return `<div class="row ${m.from}"><div class="bub" dir="${bdir}">${inner.join("")}${react}</div></div>`;
    })
    .join("");

  return page(s, TG_CSS, "tg", [
    statusBar(s.statusTime),
    `<div class="nav"><span class="back">${ICON.chev}${ch(s.header.backLabel ?? "Chats")}</span>` +
      `<div class="center">${ch(s.header.title, "nm")}${ch(s.header.subtitle, "sub")}</div>` +
      `<div class="av">${ch((s.header.title.match(/\S/g) ?? ["?"])[0])}</div></div>`,
    `<div class="thread" dir="${rtl ? "rtl" : "ltr"}"><div class="thread-inner">${rows}</div></div>`,
    `<div class="comp" dir="${rtl ? "rtl" : "ltr"}"><span class="ico">${ICON.clip}</span>` +
      `<div class="field">${ch(rtl ? "הודעה" : "Message")}${ICON.smiley}</div>` +
      `<span class="ico">${ICON.mic}</span></div>`,
    keyboard(s.keyboard),
    homeIndicator(),
  ]);
}

// ---------------------------------------------------------------------------
// Mail
// ---------------------------------------------------------------------------

const ML_CSS = `
.ml{--bg:#FFFFFF;--nav:#F9F9F9;--txt:#000;--meta:#8A8A8E;--sep:#D8D8DC;--tint:#007AFF;--home:#000;
  --quote:#8A8A8E;--qline:#C7C7CC;--bar:#F9F9F9;--card:#F2F2F7}
.ml[data-appearance="dark"]{--bg:#1C1C1E;--nav:#1C1C1E;--txt:#FFFFFF;--meta:#98989F;--sep:#38383A;
  --tint:#0A84FF;--home:#fff;--quote:#98989F;--qline:#48484A;--bar:#1C1C1E;--card:#2C2C2E}
.ml{background:var(--bg);color:var(--txt)}
.ml .statusbar{background:var(--nav);color:var(--txt)}
.ml .home-ind{background:var(--home)}
.ml .nav{flex:0 0 44px;background:var(--nav);display:flex;align-items:center;justify-content:space-between;
  padding:0 12px;border-bottom:.5px solid var(--sep)}
.ml .nav .back{color:var(--tint);font-size:17px;display:flex;align-items:center;gap:3px}
.ml .nav .ico{color:var(--tint);display:flex;align-items:center;gap:22px}
.ml .thread{justify-content:flex-start}
.ml .thread.scrolled{justify-content:flex-end}
.ml .thread-inner{padding:0}
.ml .subj{font-size:22px;font-weight:700;letter-spacing:-.5px;line-height:1.2;padding:12px 16px 10px;
  border-bottom:.5px solid var(--sep)}
.ml .mail{padding:11px 16px 14px;border-bottom:.5px solid var(--sep)}
.ml .mh{display:flex;gap:10px;align-items:flex-start}
.ml .av{width:36px;height:36px;flex:0 0 36px;border-radius:50%;display:flex;align-items:center;
  justify-content:center;color:#fff;font-size:15px;font-weight:500;
  background:linear-gradient(150deg,#8E9AA8,#5A6472)}
.ml .mhc{flex:1;min-width:0}
.ml .l1{display:flex;justify-content:space-between;align-items:baseline;gap:8px}
.ml .from{font-size:16px;font-weight:600;letter-spacing:-.2px}
.ml .when{font-size:13.5px;color:var(--meta);white-space:nowrap}
.ml .to{font-size:13.5px;color:var(--meta);margin-top:1px;display:flex;justify-content:space-between}
.ml .to .det{color:var(--tint)}
.ml .bodytxt{font-size:16px;line-height:1.44;margin-top:11px;white-space:pre-wrap}
.ml .sig{font-size:14px;line-height:1.42;color:var(--meta);margin-top:22px;white-space:pre-wrap}
.ml .more{margin-top:12px;width:34px;height:20px;border-radius:5px;background:var(--card);
  display:flex;align-items:center;justify-content:center;font-size:14px;color:var(--meta)}
.ml .hist{margin-top:12px;padding-left:10px;border-left:2px solid var(--qline);color:var(--quote);
  font-size:14.5px;line-height:1.42;white-space:pre-wrap}
.ml[dir="rtl"] .hist{border-left:none;border-right:2px solid var(--qline);padding-left:0;padding-right:10px}
.ml .toolbar{flex:0 0 46px;background:var(--bar);border-top:.5px solid var(--sep);display:flex;
  align-items:center;justify-content:space-around;color:var(--tint);font-size:19px;margin-bottom:22px}
`;

function renderMail(s) {
  const rtl = s.dir === "rtl";
  const mails = s.messages
    .map((m, i) => {
      const id = `m${i}`;
      const parts = [
        `<div class="mh"><div class="av">${ch((m.sender.match(/\S/g) ?? ["?"])[0])}</div>` +
          `<div class="mhc"><div class="l1">${ch(m.sender, "from")}${ch(m.time, "when")}</div>` +
          `<div class="to">${ch(m.to ?? (rtl ? "אל: אני" : "To: me"))}${ch(rtl ? "פרטים" : "Details", "det")}</div>` +
          `</div></div>`,
        `<div class="bodytxt" dir="${hasHebrew(m.text) ? "rtl" : "ltr"}">${body(m, id, m.text)}</div>`,
      ];
      if (m.signature) parts.push(ch(m.signature, "sig"));
      if (m.history) parts.push(`<div class="more">${ch("•••")}</div><div class="hist">${ch(m.history)}</div>`);
      return `<div class="mail">${parts.join("")}</div>`;
    })
    .join("");

  return page(s, ML_CSS, "ml", [
    statusBar(s.statusTime),
    `<div class="nav"><span class="back">${ICON.chev}${ch(s.header.backLabel ?? "Inbox")}</span>` +
      `<span class="ico">${ICON.folder}${ICON.reply}${ICON.compose}</span></div>`,
    `<div class="thread ${s.scrolled ? "scrolled" : ""}" dir="${rtl ? "rtl" : "ltr"}"><div class="thread-inner">` +
      `<div class="subj" dir="${hasHebrew(s.header.title) ? "rtl" : "ltr"}">${ch(s.header.title)}</div>` +
      `${mails}</div></div>`,
    `<div class="toolbar">${ICON.flag}${ICON.trash}${ICON.folder}${ICON.reply}${ICON.compose}</div>`,
    keyboard(s.keyboard),
    homeIndicator(),
  ]);
}

// ---------------------------------------------------------------------------

function page(scene, css, cls, parts) {
  return `<!doctype html><html lang="${scene.dir === "rtl" ? "he" : "en"}"><head><meta charset="utf-8">
<style>${BASE_CSS}${KB_CSS}${OWN_CSS}${css}</style></head><body>
<div class="screen ${cls}" data-appearance="${scene.appearance}" ${scene.dir === "rtl" ? 'dir="rtl"' : ""}>
${parts.join("\n")}
</div></body></html>`;
}

const RENDERERS = {
  WhatsApp: renderWhatsApp,
  Slack: renderSlack,
  Messages: renderIMessage,
  Telegram: renderTelegram,
  Mail: renderMail,
};

export function render(scene) {
  const fn = RENDERERS[scene.app];
  if (!fn) throw new Error(`No renderer for app "${scene.app}" (scene ${scene.id})`);
  return fn(scene);
}
