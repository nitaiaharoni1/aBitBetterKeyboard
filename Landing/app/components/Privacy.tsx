import styles from "./Privacy.module.css";

const points = [
  {
    title: "On-device first",
    body: "Suggestions and dictation run on your iPhone whenever possible.",
  },
  {
    title: "Cloud, only when you ask",
    body: "Heavier AI actions call the cloud only when you tap them.",
  },
  {
    title: "Never sold",
    body: "Your keystrokes and messages are never used for advertising.",
  },
];

export default function Privacy() {
  return (
    <section
      className={`wrap ${styles.section}`}
      aria-labelledby="privacy-title"
    >
      <p className="eyebrow">Privacy</p>
      <h2 id="privacy-title" className="section-title">
        Your words stay yours.
      </h2>
      <ul className={styles.list}>
        {points.map((point) => (
          <li key={point.title} className={styles.item}>
            <strong className={styles.itemTitle}>{point.title}</strong>
            <p className={styles.itemBody}>{point.body}</p>
          </li>
        ))}
      </ul>
    </section>
  );
}
