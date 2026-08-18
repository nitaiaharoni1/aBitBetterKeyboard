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
  globe: (
    <>
      <circle cx="12" cy="12" r="8.25" />
      <path d="M3.9 12h16.2" />
      <path d="M12 3.75c2 2.3 3 5 3 8.25s-1 5.95-3 8.25c-2-2.3-3-5-3-8.25s1-5.95 3-8.25z" />
    </>
  ),
} as const;

type StripIcon = keyof typeof stripIcons;

const waveHeights = [6, 11, 8, 14, 9, 16, 11, 7, 13, 9, 12, 6];

// Three rows of a keyboard being rearranged: one band taller than the others,
// and one key lifted out of place.
const layoutRows: { count: number; tall?: boolean; on?: number }[] = [
  { count: 9 },
  { count: 8, tall: true },
  { count: 5, on: 3 },
];

export default function Features({ t }: { t: Copy }) {
  const supporting: { icon: StripIcon; title: string; body: string }[] = [
    { icon: "check", title: t.fixTitle, body: t.fixBody },
    { icon: "bookmark", title: t.dictionaryTitle, body: t.dictionaryBody },
    { icon: "globe", title: t.switchTitle, body: t.switchBody },
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
          <div className={styles.chatMock} dir="rtl" lang="he" aria-hidden="true">
            <p className={styles.chatIn}>{t.hebrewTyped}</p>
            <p className={styles.chatChip}>{t.hebrewChip}</p>
            <p className={styles.chatOut}>{t.hebrewSent}</p>
          </div>
          <h3 className={styles.cardTitle}>{t.hebrewTitle}</h3>
          <p className={styles.cardBody}>{t.hebrewBody}</p>
        </article>
        <article className={styles.sideCard}>
          <div className={styles.layoutMock} aria-hidden="true">
            {layoutRows.map((row, rowIndex) => (
              <span key={rowIndex} className={styles.layoutRow}>
                {Array.from({ length: row.count }).map((_, keyIndex) => (
                  <span
                    key={keyIndex}
                    className={[
                      styles.layoutKey,
                      row.tall ? styles.layoutKeyTall : "",
                      row.on === keyIndex ? styles.layoutKeyOn : "",
                    ]
                      .filter(Boolean)
                      .join(" ")}
                  />
                ))}
              </span>
            ))}
          </div>
          <h3 className={styles.cardTitle}>{t.layoutsTitle}</h3>
          <p className={styles.cardBody}>{t.layoutsBody}</p>
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
