import type { Copy } from "../copy";
import { basePath } from "../site";
import styles from "./Nav.module.css";

export default function Nav({
  t,
  onToggleLocale,
}: {
  t: Copy;
  onToggleLocale: () => void;
}) {
  return (
    <header id="top" className={styles.header}>
      <nav className={`wrap ${styles.nav}`} aria-label="Main">
        <a className={styles.wordmark} href="#top">
          <img src={`${basePath}/mark.png`} alt="" width={28} height={28} />
          {t.wordmark}
        </a>
        <div className={styles.tools}>
          <button
            type="button"
            className={styles.locale}
            onClick={onToggleLocale}
            aria-label={t.localeSwitch}
          >
            {t.localeName}
          </button>
          <a className={styles.cta} href="#download">
            {t.navCta}
          </a>
        </div>
      </nav>
    </header>
  );
}
