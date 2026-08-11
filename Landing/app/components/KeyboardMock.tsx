import styles from "./KeyboardMock.module.css";

const topRow = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"];
const middleRow = ["A", "S", "D", "F", "G", "H", "J", "K", "L"];
const bottomRow = ["Z", "X", "C", "V", "B", "N", "M"];

export default function KeyboardMock() {
  return (
    <div className={styles.stage} aria-hidden="true">
      <svg
        className={styles.doodleArrow}
        viewBox="0 0 100 90"
        fill="none"
      >
        <path
          d="M8 8 C30 50 55 70 82 74"
          stroke="#ee7442"
          strokeWidth="4.5"
          strokeLinecap="round"
          pathLength={100}
        />
        <path
          d="M62 60 C70 66 78 72 84 78 C76 78 66 80 58 82"
          stroke="#ee7442"
          strokeWidth="4.5"
          strokeLinecap="round"
          strokeLinejoin="round"
          pathLength={100}
        />
      </svg>
      <div className={styles.keyboard}>
        <div className={styles.bar}>
          <span className={styles.ai}>✦</span>
          <span>I</span>
          <span>The</span>
          <span>We</span>
          <span className={styles.barIcon}>◉</span>
        </div>
        <div className={styles.row}>
          {topRow.map((letter) => (
            <span key={letter} className={styles.key}>
              {letter}
            </span>
          ))}
        </div>
        <div className={`${styles.row} ${styles.middleRow}`}>
          {middleRow.map((letter) => (
            <span key={letter} className={styles.key}>
              {letter}
            </span>
          ))}
        </div>
        <div className={styles.row}>
          <span className={`${styles.key} ${styles.dark} ${styles.wide}`}>
            ⇧
          </span>
          {bottomRow.map((letter) => (
            <span key={letter} className={styles.key}>
              {letter}
            </span>
          ))}
          <span className={`${styles.key} ${styles.soft} ${styles.wide}`}>
            ⌫
          </span>
        </div>
        <div className={styles.row}>
          <span className={`${styles.key} ${styles.dark} ${styles.wide}`}>
            123
          </span>
          <span className={`${styles.key} ${styles.soft} ${styles.wide}`}>
            ☺
          </span>
          <span className={`${styles.key} ${styles.space}`}>English</span>
          <span className={`${styles.key} ${styles.orange} ${styles.wide}`}>
            ↵
          </span>
        </div>
      </div>
      <svg
        className={styles.doodleStar}
        viewBox="0 0 40 40"
        fill="none"
      >
        <path
          d="M20 4 C20.8 14 21 26 20 36"
          stroke="#ee7442"
          strokeWidth="4"
          strokeLinecap="round"
          pathLength={100}
        />
        <path
          d="M6 13 C15 16.5 25 17 34 15"
          stroke="#ee7442"
          strokeWidth="4"
          strokeLinecap="round"
          pathLength={100}
        />
        <path
          d="M10 29 C16.5 22 24 15 31 8"
          stroke="#ee7442"
          strokeWidth="4"
          strokeLinecap="round"
          pathLength={100}
        />
      </svg>
    </div>
  );
}
