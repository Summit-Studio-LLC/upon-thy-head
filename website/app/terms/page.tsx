import type { Metadata } from "next";
import { en } from "../content";
import { Footer } from "../footer";

export const metadata: Metadata = {
  title: `${en.terms.title} · ${en.meta.title}`,
  description: en.terms.description,
  alternates: { canonical: "/terms" },
};

type Part = string | { link: string; href: string; lang?: string };

export default function Terms() {
  const c = en;
  const t = c.terms;
  return (
    <>
      <main className="wrap terms">
        <a className="terms-back" href="/">
          {t.back}
        </a>
        <h1>{t.title}</h1>
        <p className="terms-changed">{t.changed}</p>
        <p>{t.intro}</p>
        {t.sections.map((section) => (
          <section key={section.heading}>
            <h2>{section.heading}</h2>
            {section.body.map((parts: readonly Part[], i) => (
              <p key={i}>
                {parts.map((part, j) =>
                  typeof part === "string" ? (
                    part
                  ) : (
                    <a key={j} href={part.href} lang={part.lang} rel="noreferrer">
                      {part.link}
                    </a>
                  ),
                )}
              </p>
            ))}
          </section>
        ))}
      </main>
      <Footer content={c} />
    </>
  );
}
