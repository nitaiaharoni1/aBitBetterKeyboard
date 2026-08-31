import type { Copy, Locale } from "../copy";
import type { ReactNode } from "react";
import { copy } from "../copy";
import { basePath } from "../site";
import KeyboardMock from "../components/KeyboardMock";
import styles from "./StoreShot.module.css";

export function KeyboardStoreShot({
  locale,
  title,
  accent,
  subtitle,
}: {
  locale: Locale;
  title: string;
  accent: string;
  subtitle: string;
}) {
  const t: Copy = copy[locale];

  return (
    <main className={styles.page}>
      <Brand />
      <h1 className={styles.title}>
        {title} <span className={styles.accent}>{accent}</span>
      </h1>
      <p className={styles.subtitle}>{subtitle}</p>
      <div className={styles.keyboard}>
        <KeyboardMock locale={locale} t={t} />
      </div>
    </main>
  );
}

export function PrivacyStoreShot() {
  return (
    <main className={styles.page}>
      <Brand />
      <h1 className={styles.title}>
        Cloud AI, <span className={styles.accent}>only when you ask.</span>
      </h1>
      <p className={styles.subtitle}>
        Typing stays local. Cloud text and audio are off until an adult allows
        them, and every send starts with a tap.
      </p>
      <section className={styles.privacyCard} aria-label="Privacy settings">
        <p className={styles.sectionLabel}>Privacy</p>
        <PrivacyRow
          icon="☁"
          title="Allow cloud AI processing (18+)"
          detail="Only Fix, Rewrite, Reply, Tone, and Dictate send the text or audio needed for that request."
          trailing={<span className={styles.switch} />}
        />
        <PrivacyRow
          icon="⌨"
          title="Typing and suggestions"
          detail="Runs on your iPhone. Nothing is sent while you type."
          trailing={<span className={styles.localBadge}>ON DEVICE</span>}
        />
        <PrivacyRow
          icon="◉"
          title="No advertising or tracking"
          detail="Your words are never sold or used for advertising."
        />
      </section>
      <p className={styles.footnote}>
        Cloud permission can be turned off again at any time in Settings.
      </p>
    </main>
  );
}

function Brand() {
  return (
    <p className={styles.brand}>
      <img src={`${basePath}/mark.png`} alt="" width={30} height={30} />
      aBitBetterKeyboard
    </p>
  );
}

function PrivacyRow({
  icon,
  title,
  detail,
  trailing,
}: {
  icon: string;
  title: string;
  detail: string;
  trailing?: ReactNode;
}) {
  return (
    <div className={styles.privacyRow}>
      <span className={styles.icon}>{icon}</span>
      <div>
        <p className={styles.rowTitle}>{title}</p>
        <p className={styles.rowDetail}>{detail}</p>
      </div>
      {trailing}
    </div>
  );
}
