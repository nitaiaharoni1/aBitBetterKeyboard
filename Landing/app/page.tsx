import Nav from "./components/Nav";
import Hero from "./components/Hero";
import ImmersiveStory from "./components/ImmersiveStory";
import Features from "./components/Features";
import Bilingual from "./components/Bilingual";
import Privacy from "./components/Privacy";
import FinalCta from "./components/FinalCta";
import Footer from "./components/Footer";

export default function Home() {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav />
      <main id="main">
        <Hero />
        <ImmersiveStory />
        <Features />
        <Bilingual />
        <Privacy />
        <FinalCta />
      </main>
      <Footer />
    </>
  );
}
