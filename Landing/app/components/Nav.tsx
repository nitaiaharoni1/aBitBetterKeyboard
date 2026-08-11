import styles from "./Nav.module.css";

export default function Nav() {
  return (
    <header id="top" className={styles.header}>
      <nav className={`wrap ${styles.nav}`} aria-label="Main">
        <a className={styles.wordmark} href="#top">
          AIKeyboard
        </a>
        <a className={styles.cta} href="#download">
          Download
        </a>
      </nav>
    </header>
  );
}
