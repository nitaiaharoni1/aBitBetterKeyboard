import type { Copy } from "../copy";
import styles from "./FinalCta.module.css";

export default function FinalCta({ t }: { t: Copy }) {
  const steps = [
    { title: t.step1Title, body: t.step1Body },
    { title: t.step2Title, body: t.step2Body },
    { title: t.step3Title, body: t.step3Body },
  ];

  return (
    <section
      id="download"
      className={`wrap ${styles.section}`}
      aria-labelledby="cta-title"
    >
      <div className={styles.card}>
        <h2 id="cta-title" className={styles.title}>
          {t.downloadTitle}
        </h2>
        <p className={styles.subtitle}>{t.downloadSub}</p>
        <ol className={styles.steps}>
          {steps.map((step, index) => (
            <li key={step.title} className={styles.step}>
              <span className={styles.stepIndex}>{index + 1}</span>
              <strong className={styles.stepTitle}>{step.title}</strong>
              <p className={styles.stepBody}>{step.body}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
