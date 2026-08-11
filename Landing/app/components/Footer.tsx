import styles from "./Footer.module.css";

export default function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={`wrap ${styles.inner}`}>
        <span className={styles.wordmark}>AIKeyboard</span>
        <nav className={styles.links} aria-label="Footer">
          <a className={styles.link} href="#">
            App Store
          </a>
          <a className={styles.link} href="#">
            Privacy
          </a>
        </nav>
        <p className={styles.copy}>© 2026 AIKeyboard</p>
      </div>
    </footer>
  );
}
