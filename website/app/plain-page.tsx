import type { Content } from "./content";
import { Footer } from "./footer";

type Part = string | { link: string; href: string; lang?: string };
type Plain = {
  title: string;
  changed: string;
  intro: string;
  back: string;
  sections: readonly { heading: string; body: readonly (readonly Part[])[] }[];
};

/** A page of plain reading: the terms, the privacy policy, the help page. One quiet column. */
export function PlainPage({ content, page }: { content: Content; page: Plain }) {
  return (
    <>
      <main className="wrap terms">
        <a className="terms-back" href="/">
          {page.back}
        </a>
        <h1>{page.title}</h1>
        {page.changed && <p className="terms-changed">{page.changed}</p>}
        <p>{page.intro}</p>
        {page.sections.map((section) => (
          <section key={section.heading}>
            <h2>{section.heading}</h2>
            {section.body.map((parts, i) => (
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
      <Footer content={content} />
    </>
  );
}
