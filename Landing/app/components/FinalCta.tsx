import styles from "./FinalCta.module.css";

export default function FinalCta() {
  return (
    <section
      id="download"
      className={`wrap ${styles.section}`}
      aria-labelledby="cta-title"
    >
      <div className={styles.card}>
        <div className={styles.echo}>
          <p className={styles.echoText}>
            Thank you for the invite. Thursday at 7:00 works perfectly for me.
            See you then!
          </p>
          <p className={styles.echoMeta}>
            <span className={styles.echoCheck}>✓</span> Sent from the keyboard
          </p>
        </div>
        <p className={`eyebrow ${styles.eyebrow}`}>Ready when you are</p>
        <h2 id="cta-title" className={styles.title}>
          Write better in every conversation.
        </h2>
        <p className={styles.subtitle}>
          Free to download. Works in every app on your iPhone.
        </p>
        <a className={styles.button} href="#">
          Download on the App Store
        </a>
      </div>
    </section>
  );
}
