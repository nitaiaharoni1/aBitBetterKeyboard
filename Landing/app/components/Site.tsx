"use client";

import { useEffect, useState } from "react";
import { copy, type Locale } from "../copy";
import Nav from "./Nav";
import Hero from "./Hero";
import ImmersiveStory from "./ImmersiveStory";
import Features from "./Features";
import Bilingual from "./Bilingual";
import Privacy from "./Privacy";
import FinalCta from "./FinalCta";
import Footer from "./Footer";

export default function Site() {
  const [locale, setLocale] = useState<Locale>("en");
  const t = copy[locale];

  useEffect(() => {
    const stored = window.localStorage.getItem("aikeyboard-locale");
    if (stored === "he" || stored === "en") setLocale(stored);
  }, []);

  useEffect(() => {
    document.documentElement.lang = locale;
    document.documentElement.dir = locale === "he" ? "rtl" : "ltr";
    window.localStorage.setItem("aikeyboard-locale", locale);
  }, [locale]);

  return (
    <>
      <a className="skip-link" href="#main">
        {t.skip}
      </a>
      <Nav
        t={t}
        onToggleLocale={() => setLocale(locale === "en" ? "he" : "en")}
      />
      <main id="main">
        <Hero locale={locale} t={t} />
        <ImmersiveStory locale={locale} t={t} />
        <Features t={t} />
        <Bilingual t={t} />
        <Privacy t={t} />
        <FinalCta t={t} />
      </main>
      <Footer t={t} />
    </>
  );
}
