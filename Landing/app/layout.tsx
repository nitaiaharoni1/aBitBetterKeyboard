import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "aBitBetterKeyboard: A keyboard that writes with you",
  description:
    "An iOS keyboard with reply, rewrite, and dictation in the app you are already in. Hebrew and English, on the keys.",
  openGraph: {
    title: "aBitBetterKeyboard: A keyboard that writes with you",
    description:
      "Reply, rewrite, and dictate in the app you are already in. Hebrew and English.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "aBitBetterKeyboard: A keyboard that writes with you",
    description:
      "Reply, rewrite, and dictate in the app you are already in. Hebrew and English.",
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
