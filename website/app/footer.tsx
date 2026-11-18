import type { Content } from "./content";

// Summit Studio's footer, as on summitstudio.dev: its mark, its colours, its columns.
const MARK =
  "M370.999 196.5L370.973 196.544L514.997 446H0L144.023 196.543L143.999 196.5L255.314 3.78125L257.499 0L370.999 196.5ZM91.7988 393H257.499L174.63 249.531L91.7988 393ZM257.499 393H423.198L340.366 249.532L257.499 393ZM203 202.5L256.5 292L310 202.5L256.5 113L203 202.5Z";

export function Footer({ content }: { content: Content }) {
  const f = content.footer;
  return (
    <footer className="studio">
      <div className="studio-inner">
        <div className="studio-grid">
          <div>
            <a className="studio-brand" href={f.builderUrl}>
              <svg viewBox="0 0 515 446" fill="currentColor" aria-hidden="true" focusable="false">
                <path d={MARK} />
              </svg>
              <span>{f.builder}</span>
            </a>
            <p className="studio-about">{f.about}</p>
            <a className="studio-mail" href={`mailto:${f.email}`}>
              <span className="studio-mail-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" focusable="false">
                  <rect x="3" y="5" width="18" height="14" rx="2" />
                  <path d="m3.5 7 8.5 6.5L20.5 7" />
                </svg>
              </span>
              <span className="studio-mail-words">
                <span className="studio-mail-label">{f.emailLabel}</span>
                <span className="studio-mail-address">{f.email}</span>
              </span>
            </a>
          </div>
          {f.columns.map((column) => (
            <nav key={column.heading} aria-label={column.heading}>
              <h2>{column.heading}</h2>
              <ul>
                {column.links.map((link) => (
                  <li key={link.href}>
                    <a href={link.href}>{link.label}</a>
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
        <div className="studio-bar">
          <p>{f.notOfficial}</p>
          <p className="studio-credits">{f.credits}</p>
          <p>{f.rights}</p>
        </div>
      </div>
    </footer>
  );
}
