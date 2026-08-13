export function MicIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="9" y="3.5" width="6" height="11" rx="3" />
      <path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" />
    </svg>
  );
}

export function EmojiIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="9" />
      <path d="M8.5 10h.01M15.5 10h.01M8.2 14.5c1.2 1.4 2.5 2 3.8 2s2.6-.6 3.8-2" />
    </svg>
  );
}

export function Scribble({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 220 80" fill="none" aria-hidden="true">
      <path
        d="M12 44 C18 14 92 4 152 10 C206 16 222 34 214 50 C205 69 118 76 66 70 C24 65 4 58 10 42"
        stroke="#ee7442"
        strokeWidth="5"
        strokeLinecap="round"
        pathLength={100}
      />
      <path
        d="M16 52 C40 70 130 78 182 62"
        stroke="#ee7442"
        strokeWidth="3.5"
        strokeLinecap="round"
        opacity=".45"
        pathLength={100}
      />
    </svg>
  );
}

export function DoodleArrow({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 100 90" fill="none" aria-hidden="true">
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
  );
}

export function DoodleStar({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 40 40" fill="none" aria-hidden="true">
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
  );
}
