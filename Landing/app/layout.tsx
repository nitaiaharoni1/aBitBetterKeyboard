import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AIKeyboard: A keyboard that writes with you",
  description:
    "An iOS keyboard with AI text actions, voice dictation, and smart replies that understand what is on your screen, in the language you are writing.",
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
