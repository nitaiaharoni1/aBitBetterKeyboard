import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(
    "https://nitaiaharoni1.github.io/aBitBetterKeyboard/",
  ),
  title: "aBitBetterKeyboard: Hebrew autocorrect that actually works",
  description:
    "An iOS keyboard built for Hebrew. It knows what glues onto the front of a word, keeps your English words in English, and lets you rebuild the keys. Hebrew and English, on the keys.",
  openGraph: {
    title: "aBitBetterKeyboard: Hebrew autocorrect that actually works",
    description:
      "Built for Hebrew: the letters that glue onto a word, English words kept in English, and a keyboard you can rebuild.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "aBitBetterKeyboard: Hebrew autocorrect that actually works",
    description:
      "Built for Hebrew: the letters that glue onto a word, English words kept in English, and a keyboard you can rebuild.",
  },
};

export const viewport: Viewport = {
  themeColor: "#F4F3EF",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
