import type { Metadata } from "next";
import Link from "next/link";
import { publicSupportEmail } from "../site";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "What aBitBetterKeyboard does with what you type: on-device first, cloud only when you ask, never sold, and what the app counts.",
};

export default function PrivacyPage() {
  return (
    <main className="wrap privacy-page">
      <p>
        <Link href="/">aBitBetterKeyboard</Link>
      </p>
      <h1>Privacy</h1>
      <p>Last updated: August 31, 2026</p>
      <p>
        aBitBetterKeyboard is an iOS keyboard. This page explains what leaves
        your phone, why it leaves, and how long it is kept.
      </p>
      <h2>What stays on your phone</h2>
      <p>
        Typing, suggestions, your personal dictionary, and saved copy clips are
        stored on your iPhone. The keyboard works without Full Access.
      </p>
      <h2>What is sent when you ask for AI</h2>
      <p>
        Cloud AI is off until you explicitly allow it in the app. You can turn
        it off again at any time in Settings. When it is off, text and audio are
        not sent for AI processing.
      </p>
      <p>
        Cloud AI features are available only to adults 18 or older. The app asks
        you to confirm this before cloud processing can be enabled.
      </p>
      <p>
        When you tap an AI action, the selected or copied text needed for that
        action is sent to our Google Cloud Run backend and then to Google Vertex
        AI. When you use cloud dictation, the recorded WAV audio is sent through
        the same path. These actions are never run in the background on what you
        type. Screen recording is disabled in the current release, so no screen
        image is sent.
      </p>
      <p>
        The app also sends an Apple App Attest proof and a pseudonymous device
        identifier. These are used only to reject fake clients and limit abuse
        of the service.
      </p>
      <h2>Storage and retention</h2>
      <p>
        Our backend has no database. It does not write AI prompts, results,
        audio, or images to storage or logs. It holds them in memory only long
        enough to answer the request. We disable Vertex AI&apos;s optional
        project-wide memory cache. Google may still temporarily retain prompts
        for abuse monitoring under its service terms. Google processes the
        request as our cloud service provider under the{" "}
        <a href="https://cloud.google.com/terms/data-processing-addendum">
          Google Cloud Data Processing Addendum
        </a>
        . Google states that it will not use customer data to train or fine-tune
        AI models without permission. We do not use this content to train our
        own models.
      </p>
      <h2>Analytics</h2>
      <p>
        The app counts how far setup gets, whether Full Access and the keyboard
        were confirmed, and whether you come back to the app. Each event includes
        a random install identifier, the app and iOS versions, and a timestamp.
        It never includes a keystroke, correction, dictated word, AI input or
        answer, contact, or screen content. The keyboard and broadcast extensions
        send no analytics. No third-party analytics software is included.
      </p>
      <p>
        Accepted analytics events are kept in Google Cloud Logging for 30 days.
        You can turn analytics off or reset the random identifier in Settings.
        Resetting prevents future events from being connected to the old
        identifier; older events expire automatically after 30 days.
      </p>
      <h2>Your choices and deletion</h2>
      <p>
        You can use the keyboard without Full Access, avoid cloud actions, turn
        analytics off, clear learned words and copy history in the app, or
        uninstall the app to remove its local data. The app has no user account
        and the backend keeps no user-content record to delete.
      </p>
      <h2>No sale, advertising, or tracking</h2>
      <p>
        We do not sell personal data, use it for advertising, track you across
        other companies&apos; apps or websites, or use your content to train our
        own models.
      </p>
      <h2>Contact</h2>
      <p>
        aBitBetterKeyboard is published by Nitai Aharoni. For support, privacy
        questions, or a data request, email{" "}
        <a href={`mailto:${publicSupportEmail}`}>{publicSupportEmail}</a>.
      </p>
    </main>
  );
}
