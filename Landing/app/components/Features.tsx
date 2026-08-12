import type { Copy } from "../copy";
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

const waveHeights = [6, 11, 8, 14, 9, 16, 11, 7, 13, 9, 12, 6];

export default function Features({ t }: { t: Copy }) {
  const supporting: { icon: StripIcon; title: string; body: string }[] = [
    { icon: "check", title: t.grammarTitle, body: t.grammarBody },
    { icon: "bookmark", title: t.dictionaryTitle, body: t.dictionaryBody },
    { icon: "layout", title: t.layoutsTitle, body: t.layoutsBody },
  ];

  return (
    <section
      id="features"
      className={`wrap ${styles.section}`}
      aria-labelledby="features-title"
    >
      <div className={styles.header}>
        <h2 id="features-title" className="section-title">
          {t.featuresTitle}
        </h2>
        <p className="section-subtitle">{t.featuresSub}</p>
      </div>
      <div className={styles.core}>
        <article className={styles.mainCard}>
          <div className={styles.chatMock} aria-hidden="true">
            <p className={styles.chatIn}>{t.sceneIn}</p>
            <p className={styles.chatChip}>{t.screenChip}</p>
            <p className={styles.chatOut}>{t.sceneOut}</p>
          </div>
          <h3 className={styles.cardTitle}>{t.screenTitle}</h3>
          <p className={styles.cardBody}>{t.screenBody}</p>
        </article>
        <article className={styles.sideCard}>
          <div className={styles.toneMock} aria-hidden="true">
            <span className={styles.toneWord}>{t.casual}</span>
            <span className={styles.toneTrack}>
              <span className={styles.toneKnob} />
            </span>
            <span className={`${styles.toneWord} ${styles.toneOn}`}>
              {t.professional}
            </span>
          </div>
          <h3 className={styles.cardTitle}>{t.rewriteTitle}</h3>
          <p className={styles.cardBody}>{t.rewriteBody}</p>
        </article>
        <article className={styles.sideCard}>
          <div className={styles.waveMock} aria-hidden="true">
            {waveHeights.map((h, i) => (
              <span key={i} className={styles.waveBar} style={{ height: h }} />
            ))}
          </div>
          <h3 className={styles.cardTitle}>{t.dictateTitle}</h3>
          <p className={styles.cardBody}>{t.dictateBody}</p>
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
