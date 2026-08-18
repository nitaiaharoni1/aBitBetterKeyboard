import type { Copy } from "../copy";
import styles from "./Privacy.module.css";

export default function Privacy({ t }: { t: Copy }) {
  const points = [
    { title: t.privacyOnDevice, body: t.privacyOnDeviceBody },
    { title: t.privacyCloud, body: t.privacyCloudBody },
    { title: t.privacySold, body: t.privacySoldBody },
    { title: t.privacyCount, body: t.privacyCountBody },
  ];

  return (
    <section
      id="privacy"
      className={`wrap ${styles.section}`}
      aria-labelledby="privacy-title"
    >
      <h2 id="privacy-title" className="section-title">
        {t.privacyTitle}
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
