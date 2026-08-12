import KeyboardMock from "./KeyboardMock";
import { Scribble } from "./Icons";
import type { Copy, Locale } from "../copy";
import styles from "./Hero.module.css";

export default function Hero({ locale, t }: { locale: Locale; t: Copy }) {
  return (
    <section className={`wrap ${styles.hero}`} aria-labelledby="hero-title">
      <div className={styles.copy}>
        <h1 id="hero-title" className={styles.title}>
          {t.heroTitleA}
          {locale === "en" ? " " : ""}
          <span className={styles.scribbled}>
            {t.heroTitleEm}
            <Scribble className={styles.circle} />
          </span>{" "}
          {t.heroTitleB}
        </h1>
        <p className={styles.subtitle}>{t.heroSub}</p>
        <div className={styles.actions}>
          <a className={styles.primary} href="#download">
            {t.heroPrimary}
          </a>
          <a className={styles.secondary} href="#story">
            {t.heroSecondary}
          </a>
        </div>
      </div>
      <div className={styles.visual}>
        <KeyboardMock locale={locale} t={t} />
      </div>
    </section>
  );
}
