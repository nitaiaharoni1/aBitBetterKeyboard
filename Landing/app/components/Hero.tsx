import KeyboardMock from "./KeyboardMock";
import styles from "./Hero.module.css";

export default function Hero() {
  return (
    <section className={`wrap ${styles.hero}`} aria-labelledby="hero-title">
      <div className={styles.copy}>
        <p className="eyebrow">A keyboard with AI built in</p>
        <h1 id="hero-title" className={styles.title}>
          A keyboard that{" "}
          <span className={styles.scribbled}>
            writes
            <svg
              className={styles.circle}
              viewBox="0 0 220 80"
              fill="none"
              aria-hidden="true"
            >
              <path
                d="M12 44 C18 14 92 4 152 10 C206 16 222 34 214 50 C205 69 118 76 66 70 C24 65 4 58 10 42"
                stroke="#ee7442"
                strokeWidth="5"
                strokeLinecap="round"
                pathLength={100}
              />
              <path
                d="M16 52 C40 70 130 78 182 62"
                stroke="#ee7442"
                strokeWidth="3.5"
                strokeLinecap="round"
                opacity=".45"
                pathLength={100}
              />
            </svg>
          </span>{" "}
          with you.
        </h1>
        <p className={styles.subtitle}>
          Rewrite, reply, and dictate across your languages, without leaving
          the app you are in.
        </p>
        <div className={styles.actions}>
          <a className={styles.primary} href="#download">
            Download on the App Store
          </a>
          <a className={styles.secondary} href="#features">
            Explore features
          </a>
        </div>
      </div>
      <div className={styles.visual}>
        <KeyboardMock />
      </div>
    </section>
  );
}
