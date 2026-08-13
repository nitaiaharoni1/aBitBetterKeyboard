"use client";

import { useEffect, useRef } from "react";
import type { Copy, Locale } from "../copy";
import { EmojiIcon, MicIcon } from "./Icons";
import styles from "./ImmersiveStory.module.css";

const latin = {
  top: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
  mid: ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
  bot: ["Z", "X", "C", "V", "B", "N", "M"],
};

const hebrew = {
  top: ["ק", "ר", "א", "ט", "ו", "ן", "ם", "פ"],
  mid: ["ש", "ד", "ג", "כ", "ע", "י", "ח", "ל", "ך", "ף"],
  bot: ["ז", "ס", "ב", "ה", "נ", "מ", "צ", "ת", "ץ"],
};

const pressByLocale = {
  en: ["T", "H", "A", "N", "K", "S"],
  he: ["ת", "ו", "ד", "ה"],
} as const;

const waveHeights = [9, 15, 11, 19, 13, 21, 15, 10, 17, 12, 16, 9];
const miniWaveHeights = [7, 12, 9, 15, 10, 14, 8, 12, 7];

export default function ImmersiveStory({
  locale,
  t,
}: {
  locale: Locale;
  t: Copy;
}) {
  const rootRef = useRef<HTMLElement | null>(null);
  const pinRef = useRef<HTMLDivElement | null>(null);
  const rows = locale === "he" ? hebrew : latin;
  const hebrewLayout = locale === "he";
  const steps = [
    {
      id: "understand",
      title: t.storyUnderstand,
      body: t.storyUnderstandBody,
    },
    { id: "draft", title: t.storyDraft, body: t.storyDraftBody },
    { id: "refine", title: t.storyRefine, body: t.storyRefineBody },
    { id: "dictate", title: t.storyDictate, body: t.storyDictateBody },
    { id: "send", title: t.storySend, body: t.storySendBody },
  ] as const;

  useEffect(() => {
    let ctx: { revert(): void } | undefined;
    let revertMedia: (() => void) | undefined;
    let cancelled = false;

    (async () => {
      const { gsap } = await import("gsap");
      const { ScrollTrigger } = await import("gsap/ScrollTrigger");
      if (cancelled || !rootRef.current || !pinRef.current) return;
      gsap.registerPlugin(ScrollTrigger);

      ctx = gsap.context(() => {
        const media = gsap.matchMedia();
        revertMedia = () => media.revert();
        media.add(
          "(min-width: 768px) and (prefers-reduced-motion: no-preference)",
          () => {
            const root = rootRef.current;
            const pin = pinRef.current;
            if (!root || !pin) return;
            root.classList.add(styles.pinned);

            const el = (name: string) =>
              root.querySelector<HTMLElement>(`[data-el="${name}"]`)!;
            const all = (name: string) =>
              Array.from(
                root.querySelectorAll<HTMLElement>(`[data-el="${name}"]`)
              );
            const cap = (id: string) =>
              root.querySelector<HTMLElement>(`[data-step="${id}"]`)!;
            const pressKeys = pressByLocale[locale]
              .map((k) => root.querySelector<HTMLElement>(`[data-key="${k}"]`))
              .filter((k): k is HTMLElement => k !== null);

            const tl = gsap.timeline({
              defaults: { ease: "power3.out" },
              scrollTrigger: {
                trigger: pin,
                start: "top top",
                end: () => `+=${Math.round(window.innerHeight * 2.5)}`,
                scrub: 1,
                pin: true,
                pinSpacing: true,
                anticipatePin: 1,
                invalidateOnRefresh: true,
              },
            });

            tl.addLabel("understand", 0);
            tl.fromTo(
              el("doodle-path"),
              { strokeDashoffset: 1 },
              { strokeDashoffset: 0, duration: 0.45, ease: "power2.inOut" },
              0.38
            );
            tl.fromTo(
              all("doodle-head"),
              { autoAlpha: 0 },
              { autoAlpha: 1, duration: 0.12 },
              0.78
            );
            tl.fromTo(
              el("context-chip"),
              { autoAlpha: 0, y: 10, scale: 0.94 },
              { autoAlpha: 1, y: 0, scale: 1, duration: 0.3 },
              0.68
            );

            tl.addLabel("draft", 1);
            tl.to(cap("understand"), { autoAlpha: 0, y: -10, duration: 0.2 }, 1);
            tl.fromTo(
              cap("draft"),
              { autoAlpha: 0, y: 12 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              1.08
            );
            tl.fromTo(
              el("draft"),
              { autoAlpha: 0, y: 8 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              1.06
            );
            tl.fromTo(
              el("composer"),
              { autoAlpha: 0, y: 8 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              1.06
            );
            tl.to(el("strip-a"), { autoAlpha: 0, y: -6, duration: 0.2 }, 1.14);
            tl.fromTo(
              el("strip-b"),
              { autoAlpha: 0, y: 6 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              1.2
            );
            tl.fromTo(
              all("ai-btn"),
              { scale: 1 },
              {
                scale: 1.14,
                duration: 0.14,
                ease: "power2.inOut",
                yoyo: true,
                repeat: 1,
              },
              1.08
            );
            if (pressKeys.length) {
              tl.fromTo(
                pressKeys,
                { scale: 1, y: 0 },
                {
                  scale: 0.88,
                  y: 2,
                  duration: 0.11,
                  ease: "power2.inOut",
                  yoyo: true,
                  repeat: 1,
                  stagger: 0.09,
                },
                1.24
              );
            }
            tl.to(
              [el("doodle-path"), ...all("doodle-head")],
              { autoAlpha: 0, duration: 0.2 },
              1.82
            );

            tl.addLabel("refine", 2);
            tl.to(cap("draft"), { autoAlpha: 0, y: -10, duration: 0.2 }, 2);
            tl.fromTo(
              cap("refine"),
              { autoAlpha: 0, y: 12 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              2.08
            );
            tl.fromTo(
              el("panel-rewrite"),
              { autoAlpha: 0, y: 10, scale: 0.96 },
              { autoAlpha: 1, y: 0, scale: 1, duration: 0.3 },
              2.06
            );
            tl.to(el("rough"), { autoAlpha: 0, y: -4, duration: 0.25 }, 2.42);
            tl.fromTo(
              el("refined"),
              { autoAlpha: 0, y: 4 },
              { autoAlpha: 1, y: 0, duration: 0.3 },
              2.46
            );
            tl.to(
              el("knob"),
              {
                x: () => {
                  const track = el("tone-track");
                  const knob = el("knob");
                  const travel = track.clientWidth - knob.offsetWidth - 4;
                  return document.documentElement.dir === "rtl"
                    ? -travel
                    : travel;
                },
                duration: 0.35,
                ease: "power3.inOut",
              },
              2.42
            );

            tl.addLabel("dictate", 3);
            tl.to(cap("refine"), { autoAlpha: 0, y: -10, duration: 0.2 }, 3);
            tl.fromTo(
              cap("dictate"),
              { autoAlpha: 0, y: 12 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              3.08
            );
            tl.to(
              el("panel-rewrite"),
              { autoAlpha: 0, y: 8, duration: 0.22 },
              3.04
            );
            tl.fromTo(
              el("panel-wave"),
              { autoAlpha: 0, y: 10 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              3.16
            );
            tl.fromTo(
              el("mic-dot"),
              { autoAlpha: 0, scale: 0.5 },
              { autoAlpha: 1, scale: 1, duration: 0.2 },
              3.16
            );
            tl.fromTo(
              all("wave-bar"),
              { scaleY: 0.25 },
              {
                scaleY: 1,
                duration: 0.07,
                ease: "power1.inOut",
                yoyo: true,
                repeat: 3,
                stagger: 0.03,
              },
              3.2
            );
            tl.fromTo(
              el("dictated"),
              { autoAlpha: 0, y: 5 },
              { autoAlpha: 1, y: 0, duration: 0.3 },
              3.48
            );
            tl.to(
              el("panel-wave"),
              { autoAlpha: 0, y: -6, duration: 0.22 },
              3.82
            );
            tl.to(
              el("mic-dot"),
              { autoAlpha: 0, scale: 0.5, duration: 0.18 },
              3.84
            );

            tl.addLabel("send", 4);
            tl.to(cap("dictate"), { autoAlpha: 0, y: -10, duration: 0.2 }, 4);
            tl.fromTo(
              cap("send"),
              { autoAlpha: 0, y: 12 },
              { autoAlpha: 1, y: 0, duration: 0.25 },
              4.08
            );
            tl.to(el("draft"), { autoAlpha: 0, y: -12, duration: 0.25 }, 4.06);
            tl.to(el("composer"), { autoAlpha: 0, y: -12, duration: 0.25 }, 4.06);
            tl.to(
              el("context-chip"),
              { autoAlpha: 0, y: -8, duration: 0.25 },
              4.06
            );
            tl.fromTo(
              el("msg-out"),
              { autoAlpha: 0, y: 26, scale: 0.94 },
              { autoAlpha: 1, y: 0, scale: 1, duration: 0.45 },
              4.16
            );
            tl.to(el("kb"), { autoAlpha: 0.35, duration: 0.4 }, 4.28);
            tl.fromTo(
              el("sent-tag"),
              { autoAlpha: 0, scale: 0.6 },
              { autoAlpha: 1, scale: 1, duration: 0.25, ease: "power3.out" },
              4.5
            );
            tl.to({}, { duration: 0.35 }, 4.75);

            tl.fromTo(
              el("progress"),
              { scaleX: 0 },
              { scaleX: 1, ease: "none", duration: tl.duration() },
              0
            );

            return () => {
              root.classList.remove(styles.pinned);
            };
          }
        );
      }, rootRef);
    })();

    return () => {
      cancelled = true;
      revertMedia?.();
      ctx?.revert();
    };
  }, [locale]);

  return (
    <section
      id="story"
      ref={rootRef}
      className={styles.root}
      aria-labelledby="story-title"
    >
      <div ref={pinRef} className={styles.pin}>
        <div className={`wrap ${styles.head}`}>
          <h2 id="story-title" className="section-title">
            {t.storyTitle}
          </h2>
          <p className="section-subtitle">{t.storySub}</p>
          <div className={styles.progress} aria-hidden="true">
            <span className={styles.progressFill} data-el="progress" />
          </div>
        </div>
        <div className={`wrap ${styles.scene}`}>
          <ol className={styles.steps}>
            {steps.map((step) => (
              <li key={step.id} className={styles.step} data-step={step.id}>
                <h3 className={styles.stepTitle}>{step.title}</h3>
                <p className={styles.stepBody}>{step.body}</p>
                <div className={styles.stepVisual} aria-hidden="true">
                  {step.id === "understand" && (
                    <div className={styles.miniChat}>
                      <p className={styles.miniBubble}>{t.sceneIn}</p>
                      <p className={styles.miniChip}>{t.storyChip}</p>
                    </div>
                  )}
                  {step.id === "draft" && (
                    <div className={styles.miniPills}>
                      {t.suggestions.map((word) => (
                        <span key={word}>{word}</span>
                      ))}
                    </div>
                  )}
                  {step.id === "refine" && (
                    <div className={styles.miniTone}>
                      <span>{t.casual}</span>
                      <span className={styles.miniTrack}>
                        <span className={styles.miniKnob} />
                      </span>
                      <span className={styles.miniToneActive}>
                        {t.professional}
                      </span>
                    </div>
                  )}
                  {step.id === "dictate" && (
                    <div className={styles.miniDictate}>
                      <span className={styles.miniWave}>
                        {miniWaveHeights.map((h, i) => (
                          <span
                            key={i}
                            className={styles.miniWaveBar}
                            style={{ height: h }}
                          />
                        ))}
                      </span>
                      <p className={styles.miniSentence}>
                        &ldquo;{t.storySpoken}&rdquo;
                      </p>
                    </div>
                  )}
                  {step.id === "send" && (
                    <div className={styles.miniMsg}>
                      <p>{t.storyOut}</p>
                      <span className={styles.miniSent}>{t.storySent}</span>
                    </div>
                  )}
                </div>
              </li>
            ))}
          </ol>
          <div className={styles.stage} aria-hidden="true">
            <div className={styles.phone}>
              <div className={styles.chat} dir={hebrewLayout ? "rtl" : "ltr"}>
                <div className={styles.msgIn} data-el="msg-in">
                  <span className={styles.msgName}>{t.sceneFrom}</span>
                  <p className={styles.msgText}>{t.sceneIn}</p>
                </div>
                <div className={styles.msgOut} data-el="msg-out">
                  <p className={styles.msgText}>{t.storyOut}</p>
                  <span className={styles.sentTag} data-el="sent-tag">
                    {t.storySent}
                  </span>
                </div>
              </div>
              <div className={styles.contextChip} data-el="context-chip">
                {t.storyChip}
              </div>
              <svg className={styles.doodle} viewBox="0 0 110 120" fill="none">
                <path
                  data-el="doodle-path"
                  className={styles.doodlePath}
                  d="M76 6 C50 34 88 54 54 84 C40 96 32 104 28 112"
                  stroke="#ee7442"
                  strokeWidth="4"
                  strokeLinecap="round"
                  pathLength={1}
                />
                <path
                  data-el="doodle-head"
                  d="M28 112 L14 97"
                  stroke="#ee7442"
                  strokeWidth="4"
                  strokeLinecap="round"
                />
                <path
                  data-el="doodle-head"
                  d="M28 112 L46 104"
                  stroke="#ee7442"
                  strokeWidth="4"
                  strokeLinecap="round"
                />
              </svg>
              <div className={styles.composer} dir={hebrewLayout ? "rtl" : "ltr"} data-el="composer">
                <p className={styles.draft} data-el="draft">
                  <span className={styles.draftStack}>
                    <span data-el="rough">{t.storyRough}</span>
                    <span data-el="refined">{t.storyRefined}</span>
                  </span>
                  <span data-el="dictated"> {t.storySpoken}</span>
                </p>
                <span className={styles.sendBtn}>↑</span>
              </div>
              <div className={styles.kb} data-el="kb" dir="ltr">
                <div className={styles.barSlot}>
                  <div
                    className={`${styles.bar} ${styles.strip}`}
                    data-el="strip-a"
                  >
                    <span />
                    <span />
                    <span />
                  </div>
                  <div
                    className={`${styles.bar} ${styles.strip}`}
                    data-el="strip-b"
                  >
                    {t.suggestions.map((word) => (
                      <span key={word}>{word}</span>
                    ))}
                  </div>
                  <div
                    className={`${styles.bar} ${styles.panel}`}
                    data-el="panel-rewrite"
                  >
                    <span className={styles.panelLabel}>{t.actions[2]}</span>
                    <span className={styles.tone}>
                      <span className={styles.toneWord}>{t.casual}</span>
                      <span className={styles.toneTrack} data-el="tone-track">
                        <span className={styles.knob} data-el="knob" />
                      </span>
                      <span
                        className={`${styles.toneWord} ${styles.toneActive}`}
                      >
                        {t.professional}
                      </span>
                    </span>
                  </div>
                  <div
                    className={`${styles.bar} ${styles.panel}`}
                    data-el="panel-wave"
                  >
                    <span className={styles.recDot} />
                    <span className={styles.wave}>
                      {waveHeights.map((h, i) => (
                        <span
                          key={i}
                          className={styles.waveBar}
                          data-el="wave-bar"
                          style={{ height: h }}
                        />
                      ))}
                    </span>
                    <span className={styles.waveLabel}>{t.listening}</span>
                  </div>
                </div>
                <div className={styles.kbRow}>
                  {rows.top.map((k) => (
                    <span key={k} className={styles.key} data-key={k}>
                      {k}
                    </span>
                  ))}
                  {hebrewLayout ? (
                    <span
                      className={`${styles.key} ${styles.keySoft} ${styles.keyWide}`}
                    >
                      ⌫
                    </span>
                  ) : null}
                </div>
                <div className={styles.kbRow}>
                  {rows.mid.map((k) => (
                    <span key={k} className={styles.key} data-key={k}>
                      {k}
                    </span>
                  ))}
                </div>
                <div className={styles.kbRow}>
                  {hebrewLayout ? null : (
                    <span
                      className={`${styles.key} ${styles.keyDark} ${styles.keyWide}`}
                    >
                      ⇧
                    </span>
                  )}
                  {rows.bot.map((k) => (
                    <span key={k} className={styles.key} data-key={k}>
                      {k}
                    </span>
                  ))}
                  {hebrewLayout ? null : (
                    <span
                      className={`${styles.key} ${styles.keySoft} ${styles.keyWide}`}
                    >
                      ⌫
                    </span>
                  )}
                </div>
                <div className={styles.kbRow}>
                  <span
                    className={`${styles.key} ${styles.keyDark} ${styles.keyWide}`}
                  >
                    123
                  </span>
                  <span className={`${styles.key} ${styles.keySpace}`}>
                    {t.space}
                  </span>
                  <span
                    className={`${styles.key} ${styles.keyOrange} ${styles.keyWide}`}
                  >
                    ↵
                  </span>
                </div>
                <div className={styles.actions}>
                  <span className={styles.action}>
                    <EmojiIcon />
                  </span>
                  <span
                    className={`${styles.action} ${styles.actionLive}`}
                    data-el="ai-btn"
                  >
                    {t.actions[0]}
                  </span>
                  <span className={styles.action}>{t.actions[1]}</span>
                  <span className={styles.action}>{t.actions[2]}</span>
                  <span className={`${styles.action} ${styles.actionMic}`}>
                    <MicIcon />
                    <span>{t.dictate}</span>
                    <span className={styles.micDot} data-el="mic-dot" />
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
