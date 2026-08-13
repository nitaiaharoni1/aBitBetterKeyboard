import type { Copy } from "../copy";
import styles from "./Footer.module.css";

export default function Footer({ t }: { t: Copy }) {
  return (
    <footer className={styles.footer}>
      <div className={`wrap ${styles.inner}`}>
        <span className={styles.wordmark}>
          <img src="/mark.png" alt="" width={22} height={22} />
          {t.wordmark}
        </span>
        <nav className={styles.links} aria-label="Footer">
          <a className={styles.link} href="#download">
            {t.footerStore}
          </a>
          <a className={styles.link} href="/privacy">
            {t.footerPrivacy}
          </a>
        </nav>
        <p className={styles.copy}>{t.footerCopy}</p>
      </div>
    </footer>
  );
}
