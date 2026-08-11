"use client";

import { useEffect, useRef } from "react";
import styles from "./ImmersiveStory.module.css";

const steps = [
  {
    id: "understand",
    index: "01",
    title: "Understand",
    body: "Screen Context reads the conversation and sees Maya asking about Thursday.",
  },
  {
    id: "draft",
    index: "02",
    title: "Draft",
    body: "A fitting reply is written for you, right inside the message field.",
  },
  {
    id: "refine",
    index: "03",
    title: "Refine",
    body: "Rewrite moves the tone from casual to professional in one tap.",
  },
  {
    id: "dictate",
    index: "04",
    title: "Dictate",
    body: "Speak one more sentence. It lands in the message, typed and punctuated.",
  },
  {
    id: "send",
    index: "05",
    title: "Send",
    body: "The finished message lifts into the chat. You never left the keyboard.",
  },
] as const;

const topRow = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"];
const midRow = ["A", "S", "D", "F", "G", "H", "J", "K", "L"];
const botRow = ["Z", "X", "C", "V", "B", "N", "M"];
const pressSequence = ["T", "H", "A", "N", "K", "S"];
const waveHeights = [9, 15, 11, 19, 13, 21, 15, 10, 17, 12, 16, 9];
const miniWaveHeights = [7, 12, 9, 15, 10, 14, 8, 12, 7];

export default function ImmersiveStory() {
  const rootRef = useRef<HTMLElement | null>(null);
  const pinRef = useRef<HTMLDivElement | null>(null);

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
            const pressKeys = pressSequence
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
              el("msg-in"),
              { autoAlpha: 0, y: 14, scale: 0.96 },
              { autoAlpha: 1, y: 0, scale: 1, duration: 0.3 },
              0.05
            );
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
                  return track.clientWidth - knob.offsetWidth - 4;
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
  }, []);

  return (
    <section
      id="story"
      ref={rootRef}
      className={styles.root}
      aria-labelledby="story-title"
    >
      <div ref={pinRef} className={styles.pin}>
        <div className={`wrap ${styles.head}`}>
          <p className="eyebrow">One tap above the keys</p>
          <h2 id="story-title" className="section-title">
            Watch one message come together.
          </h2>
          <div className={styles.progress} aria-hidden="true">
            <span className={styles.progressFill} data-el="progress" />
          </div>
        </div>
        <div className={`wrap ${styles.scene}`}>
          <ol className={styles.steps}>
            {steps.map((step) => (
              <li key={step.id} className={styles.step} data-step={step.id}>
                <span className={styles.stepIndex}>{step.index}</span>
                <h3 className={styles.stepTitle}>{step.title}</h3>
                <p className={styles.stepBody}>{step.body}</p>
                <div className={styles.stepVisual} aria-hidden="true">
                  {step.id === "understand" && (
                    <div className={styles.miniChat}>
                      <p className={styles.miniBubble}>
                        Want to grab dinner Thursday night?
                      </p>
                      <p className={styles.miniChip}>
                        ✦ Screen Context: dinner on Thursday
                      </p>
                    </div>
                  )}
                  {step.id === "draft" && (
                    <div className={styles.miniPills}>
                      <span>Sounds good</span>
                      <span>Thursday works</span>
                      <span>See you then</span>
                    </div>
                  )}
                  {step.id === "refine" && (
                    <div className={styles.miniTone}>
                      <span>Casual</span>
                      <span className={styles.miniTrack}>
                        <span className={styles.miniKnob} />
                      </span>
                      <span className={styles.miniToneActive}>
                        Professional
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
                        &ldquo;See you then!&rdquo;
                      </p>
                    </div>
                  )}
                  {step.id === "send" && (
                    <div className={styles.miniMsg}>
                      <p>
                        Thank you for the invite. Thursday at 7:00 works
                        perfectly for me. See you then!
                      </p>
                      <span className={styles.miniSent}>✓ Sent</span>
                    </div>
                  )}
                </div>
              </li>
            ))}
          </ol>
          <div className={styles.stage} aria-hidden="true">
            <div className={styles.phone}>
              <div className={styles.chat}>
                <div className={styles.msgIn} data-el="msg-in">
                  <span className={styles.msgName}>Maya</span>
                  <p className={styles.msgText}>
                    Want to grab dinner Thursday night?
                  </p>
                </div>
                <div className={styles.msgOut} data-el="msg-out">
                  <p className={styles.msgText}>
                    Thank you for the invite. Thursday at 7:00 works perfectly
                    for me. See you then!
                  </p>
                  <span className={styles.sentTag} data-el="sent-tag">
                    ✓ Sent
                  </span>
                </div>
              </div>
              <svg
                className={styles.doodle}
                viewBox="0 0 110 120"
                fill="none"
              >
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
                  d="M28 112 L46 104"
                  stroke="#ee7442"
                  strokeWidth="4"
                  strokeLinecap="round"
                />
                <path
                  data-el="doodle-head"
                  d="M28 112 L34 128"
                  stroke="#ee7442"
                  strokeWidth="4"
                  strokeLinecap="round"
                />
              </svg>
              <div className={styles.contextChip} data-el="context-chip">
                <span className={styles.chipSpark}>✦</span>
                <span>
                  Screen Context: Maya asked about dinner on Thursday
                </span>
              </div>
              <div className={styles.composer}>
                <p className={styles.draft} data-el="draft">
                  <span className={styles.draftStack}>
                    <span data-el="rough">Thanks! Thursday at 7 works.</span>
                    <span data-el="refined">
                      Thank you for the invite. Thursday at 7:00 works
                      perfectly for me.
                    </span>
                  </span>
                  <span data-el="dictated"> See you then!</span>
                </p>
                <span className={styles.sendBtn}>↑</span>
              </div>
              <div className={styles.kb} data-el="kb">
                <div className={styles.barSlot}>
                  <div className={`${styles.bar} ${styles.strip}`} data-el="strip-a">
                    <span className={styles.aiBtn} data-el="ai-btn">
                      ✦
                    </span>
                    <span>I</span>
                    <span>The</span>
                    <span>We</span>
                    <span className={styles.barDot}>◉</span>
                  </div>
                  <div className={`${styles.bar} ${styles.strip}`} data-el="strip-b">
                    <span className={styles.aiBtn} data-el="ai-btn">
                      ✦
                    </span>
                    <span>Sounds good</span>
                    <span>Thursday works</span>
                    <span>See you then</span>
                    <span className={styles.barDot}>◉</span>
                  </div>
                  <div
                    className={`${styles.bar} ${styles.panel}`}
                    data-el="panel-rewrite"
                  >
                    <span className={styles.panelLabel}>✦ Rewrite</span>
                    <span className={styles.tone}>
                      <span className={styles.toneWord}>Casual</span>
                      <span className={styles.toneTrack} data-el="tone-track">
                        <span className={styles.knob} data-el="knob" />
                      </span>
                      <span
                        className={`${styles.toneWord} ${styles.toneActive}`}
                      >
                        Professional
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
                    <span className={styles.waveLabel}>Listening</span>
                  </div>
                </div>
                <div className={styles.kbRow}>
                  {topRow.map((k) => (
                    <span key={k} className={styles.key} data-key={k}>
                      {k}
                    </span>
                  ))}
                </div>
                <div className={styles.kbRow}>
                  {midRow.map((k) => (
                    <span key={k} className={styles.key} data-key={k}>
                      {k}
                    </span>
                  ))}
                </div>
                <div className={styles.kbRow}>
                  <span
                    className={`${styles.key} ${styles.keyDark} ${styles.keyWide}`}
                  >
                    ⇧
                  </span>
                  {botRow.map((k) => (
                    <span key={k} className={styles.key} data-key={k}>
                      {k}
                    </span>
                  ))}
                  <span
                    className={`${styles.key} ${styles.keySoft} ${styles.keyWide}`}
                  >
                    ⌫
                  </span>
                </div>
                <div className={styles.kbRow}>
                  <span
                    className={`${styles.key} ${styles.keyDark} ${styles.keyWide} ${styles.micKey}`}
                  >
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="1.8"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <rect x="9" y="3.5" width="6" height="11" rx="3" />
                      <path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" />
                    </svg>
                    <span className={styles.micDot} data-el="mic-dot" />
                  </span>
                  <span className={`${styles.key} ${styles.keySpace}`}>
                    English
                  </span>
                  <span
                    className={`${styles.key} ${styles.keyOrange} ${styles.keyWide}`}
                  >
                    ↵
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
