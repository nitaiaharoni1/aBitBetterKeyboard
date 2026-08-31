import Link from "next/link";
import type { Copy } from "../copy";
import { basePath } from "../site";
import styles from "./Footer.module.css";

export default function Footer({ t }: { t: Copy }) {
  return (
    <footer className={styles.footer}>
      <div className={`wrap ${styles.inner}`}>
        <span className={styles.wordmark}>
          <img src={`${basePath}/mark.png`} alt="" width={22} height={22} />
          {t.wordmark}
        </span>
        <nav className={styles.links} aria-label="Footer">
          <a className={styles.link} href="#download">
            {t.footerStore}
          </a>
          <Link className={styles.link} href="/privacy">
            {t.footerPrivacy}
          </Link>
          <Link className={styles.link} href="/support">
            {t.footerSupport}
          </Link>
        </nav>
        <p className={styles.copy}>{t.footerCopy}</p>
      </div>
    </footer>
  );
}
