import type { Metadata } from "next";
import Link from "next/link";
import { publicSupportEmail } from "../site";

export const metadata: Metadata = {
  title: "Support",
  description: "Help and contact information for aBitBetterKeyboard.",
};

export default function SupportPage() {
  return (
    <main className="wrap privacy-page">
      <p>
        <Link href="/">aBitBetterKeyboard</Link>
      </p>
      <h1>Support</h1>
      <p>
        For setup help, a bug report, a privacy question, or a data request,
        email <a href={`mailto:${publicSupportEmail}`}>{publicSupportEmail}</a>.
      </p>
      <h2>Before you write</h2>
      <p>
        Please include your iPhone model, iOS version, app version, and the step
        where the problem happened. Never send a password, API key, private
        message, dictated audio, or other sensitive content.
      </p>
      <h2>Useful checks</h2>
      <p>
        Add the keyboard under Settings &gt; General &gt; Keyboard &gt; Keyboards.
        Typing works without Full Access. Shared settings and optional cloud
        features need Full Access. Cloud AI is off by default and is available
        only to adults 18 or older.
      </p>
      <p>
        Read the <Link href="/privacy">privacy policy</Link> for details about
        on-device data, optional cloud processing, analytics, and deletion.
      </p>
    </main>
  );
}
