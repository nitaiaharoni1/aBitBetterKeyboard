import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "What aBitBetterKeyboard does with what you type: on-device first, cloud only when you ask, never sold.",
};

export default function PrivacyPage() {
  return (
    <main className="wrap privacy-page">
      <p>
        <Link href="/">aBitBetterKeyboard</Link>
      </p>
      <h1>Privacy</h1>
      <p>
        aBitBetterKeyboard is an iOS keyboard. This page is what the product does with
        what you type.
      </p>
      <h2>On the phone first</h2>
      <p>
        Suggestions and dictation run on your iPhone whenever they can. The
        keyboard can type without Full Access. Reply, Rewrite, and cloud
        dictation need Full Access because they have to read or send text.
      </p>
      <h2>Cloud, only when you tap</h2>
      <p>
        Heavier AI actions call the cloud only when you ask for them. They are
        not run in the background on what you type.
      </p>
      <h2>Never sold</h2>
      <p>
        Keystrokes and messages are not used for advertising, and they are not
        sold.
      </p>
    </main>
  );
}
