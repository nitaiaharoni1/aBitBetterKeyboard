import styles from "./Bilingual.module.css";

const samples: { lang: string; label: string; sentence: string; rtl?: boolean }[] = [
  { lang: "en", label: "English", sentence: "See you on Thursday." },
  { lang: "he", label: "עברית", sentence: "נתראה ביום חמישי.", rtl: true },
  { lang: "es", label: "Español", sentence: "Nos vemos el jueves." },
  { lang: "fr", label: "Français", sentence: "On se voit jeudi." },
  { lang: "ar", label: "العربية", sentence: "نراك يوم الخميس.", rtl: true },
  { lang: "de", label: "Deutsch", sentence: "Bis Donnerstag." },
];

export default function Bilingual() {
  return (
    <section
      className={`wrap ${styles.section}`}
      aria-labelledby="languages-title"
    >
      <div className={styles.header}>
        <p className="eyebrow">Multilingual by design</p>
        <h2 id="languages-title" className={`section-title ${styles.title}`}>
          Write in the language you are thinking in.
          <svg
            className={styles.swash}
            viewBox="0 0 300 22"
            fill="none"
            aria-hidden="true"
          >
            <path
              d="M4 12 C70 20 180 20 296 8"
              stroke="#ee7442"
              strokeWidth="5"
              strokeLinecap="round"
              pathLength={100}
            />
          </svg>
        </h2>
        <p className="section-subtitle">
          Suggestions, corrections, and AI actions follow you across your
          languages, in either direction.
        </p>
      </div>
      <div className={styles.card}>
        <ul className={styles.panorama}>
          {samples.map((sample) => (
            <li
              key={sample.lang}
              className={styles.cell}
              lang={sample.lang}
              dir={sample.rtl ? "rtl" : "ltr"}
            >
              <p className={styles.label}>{sample.label}</p>
              <p className={styles.sentence}>{sample.sentence}</p>
            </li>
          ))}
        </ul>
        <p className={styles.footnote}>
          Custom layouts shape the keys to your hands, and your personal
          dictionary carries your names and terms into every conversation.
        </p>
      </div>
    </section>
  );
}
