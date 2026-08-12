import type { Copy, Locale } from "../copy";
import { EmojiIcon, MicIcon } from "./Icons";
import styles from "./KeyboardMock.module.css";

const latin = {
  top: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
  mid: ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
  bot: ["Z", "X", "C", "V", "B", "N", "M"],
};

const hebrew = {
  top: ["ק", "ר", "א", "ט", "ו", "ן", "ם", "פ"],
  mid: ["ש", "ד", "ג", "כ", "ע", "י", "ח", "ל", "ך", "ף"],
  bot: ["ז", "ס", "ב", "ה", "נ", "מ", "צ", "ת", "ץ"],
};

export default function KeyboardMock({
  locale,
  t,
}: {
  locale: Locale;
  t: Copy;
}) {
  const rows = locale === "he" ? hebrew : latin;
  const hebrewLayout = locale === "he";

  return (
    <div className={styles.stage} aria-hidden="true">
      <div
        className={styles.scene}
        dir={hebrewLayout ? "rtl" : "ltr"}
      >
        <p className={styles.msgIn}>
          <span className={styles.msgName}>{t.sceneFrom}</span>
          {t.sceneIn}
        </p>
        <p className={styles.msgOut}>{t.sceneOut}</p>
      </div>
      <div className={styles.keyboard} dir="ltr">
        <div className={styles.bar}>
          {t.suggestions.map((word) => (
            <span key={word}>{word}</span>
          ))}
        </div>
        <div className={`${styles.row} ${hebrewLayout ? styles.count8 : styles.count10}`}>
          {rows.top.map((letter) => (
            <span key={letter} className={styles.key}>
              {letter}
            </span>
          ))}
          {hebrewLayout ? (
            <span className={`${styles.key} ${styles.soft} ${styles.wide}`}>
              ⌫
            </span>
          ) : null}
        </div>
        <div className={`${styles.row} ${hebrewLayout ? styles.count10 : styles.count9}`}>
          {rows.mid.map((letter) => (
            <span key={letter} className={styles.key}>
              {letter}
            </span>
          ))}
        </div>
        <div className={`${styles.row} ${hebrewLayout ? styles.count9 : styles.count7}`}>
          {hebrewLayout ? null : (
            <span className={`${styles.key} ${styles.dark} ${styles.wide}`}>
              ⇧
            </span>
          )}
          {rows.bot.map((letter) => (
            <span key={letter} className={styles.key}>
              {letter}
            </span>
          ))}
          {hebrewLayout ? null : (
            <span className={`${styles.key} ${styles.soft} ${styles.wide}`}>
              ⌫
            </span>
          )}
        </div>
        <div className={styles.row}>
          <span className={`${styles.key} ${styles.dark} ${styles.wide}`}>
            123
          </span>
          <span className={`${styles.key} ${styles.space}`}>{t.space}</span>
          <span className={`${styles.key} ${styles.orange} ${styles.wide}`}>
            ↵
          </span>
        </div>
        <div className={styles.actions}>
          <span className={styles.action}>
            <EmojiIcon />
          </span>
          <span className={`${styles.action} ${styles.actionLive}`}>
            {t.actions[0]}
          </span>
          <span className={styles.action}>{t.actions[1]}</span>
          <span className={styles.action}>{t.actions[2]}</span>
          <span className={`${styles.action} ${styles.actionMic}`}>
            <MicIcon />
            <span>{t.dictate}</span>
          </span>
        </div>
      </div>
    </div>
  );
}
