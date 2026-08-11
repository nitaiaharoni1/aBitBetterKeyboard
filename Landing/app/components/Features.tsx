import styles from "./Features.module.css";

const stripIcons = {
  check: (
    <>
      <circle cx="12" cy="12" r="8.25" />
      <path d="M8.4 12.3l2.4 2.4 4.8-5" />
    </>
  ),
  bookmark: (
    <path d="M8.75 3h6.5A1.75 1.75 0 0 1 17 4.75V21l-5-3.75L7 21V4.75A1.75 1.75 0 0 1 8.75 3z" />
  ),
  layout: (
    <>
      <rect x="4" y="5" width="16" height="14" rx="3" />
      <path d="M7.6 9.4h1.8M11.1 9.4h1.8M14.6 9.4h1.8M7.6 12.4h1.8M11.1 12.4h1.8M14.6 12.4h1.8M9.2 15.4h5.6" />
    </>
  ),
} as const;

type StripIcon = keyof typeof stripIcons;

const supporting: { icon: StripIcon; title: string; body: string }[] = [
  {
    icon: "check",
    title: "Grammar on the spot",
    body: "Spelling and grammar fixed in place, in the language you are writing.",
  },
  {
    icon: "bookmark",
    title: "Personal dictionary",
    body: "Names, slang, and terms you teach it once, suggested forever.",
  },
  {
    icon: "layout",
    title: "Custom layouts",
    body: "Arrange the keys the way your hands expect them.",
  },
];

const waveHeights = [6, 11, 8, 14, 9, 16, 11, 7, 13, 9, 12, 6];

export default function Features() {
  return (
    <section
      id="features"
      className={`wrap ${styles.section}`}
      aria-labelledby="features-title"
    >
      <div className={styles.header}>
        <p className="eyebrow">Features</p>
        <h2 id="features-title" className="section-title">
          The AI core, built into the keys.
        </h2>
        <p className="section-subtitle">
          Three tools do the heavy lifting. The rest quietly keeps your typing
          clean.
        </p>
      </div>
      <div className={styles.core}>
        <article className={styles.mainCard}>
          <div className={styles.chatMock} aria-hidden="true">
            <p className={styles.chatIn}>Want to grab dinner Thursday night?</p>
            <p className={styles.chatChip}>
              <span className={styles.chatSpark}>✦</span> Screen Context read
              the invitation
            </p>
            <p className={styles.chatOut}>
              Thursday at 7 works perfectly. See you then!
            </p>
          </div>
          <h3 className={styles.cardTitle}>Screen Context</h3>
          <p className={styles.cardBody}>
            When you ask, the keyboard reads the conversation on your screen
            and drafts a reply that fits the moment, instead of starting from
            zero.
          </p>
        </article>
        <article className={styles.sideCard}>
          <div className={styles.toneMock} aria-hidden="true">
            <span className={styles.toneWord}>Casual</span>
            <span className={styles.toneTrack}>
              <span className={styles.toneKnob} />
            </span>
            <span className={`${styles.toneWord} ${styles.toneOn}`}>
              Professional
            </span>
          </div>
          <h3 className={styles.cardTitle}>Rewrite</h3>
          <p className={styles.cardBody}>
            Reword any sentence, or shift its tone from casual to professional
            in one tap.
          </p>
        </article>
        <article className={styles.sideCard}>
          <div className={styles.waveMock} aria-hidden="true">
            {waveHeights.map((h, i) => (
              <span key={i} className={styles.waveBar} style={{ height: h }} />
            ))}
          </div>
          <h3 className={styles.cardTitle}>Dictation</h3>
          <p className={styles.cardBody}>
            Speak naturally. It types, punctuates, and hears when you are
            done.
          </p>
        </article>
      </div>
      <ul className={styles.strip}>
        {supporting.map((item) => (
          <li key={item.title} className={styles.stripItem}>
            <span className={styles.stripChip}>
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.6"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                {stripIcons[item.icon]}
              </svg>
            </span>
            <div>
              <strong className={styles.stripTitle}>{item.title}</strong>
              <p className={styles.stripBody}>{item.body}</p>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
