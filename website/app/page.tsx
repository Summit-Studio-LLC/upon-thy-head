import type { CSSProperties } from "react";
import { en } from "./content";
import { Footer } from "./footer";
import { PressLink, Reveal, RevealWords } from "./reveal";
import { Sky } from "./sky";
import { AppIcon, Shot } from "./slots";

// The ring: one shallow curve across the sky. `at` is how far along it a light sits (0 to 1).
type Curve = { from: readonly [number, number]; bend: readonly [number, number]; to: readonly [number, number] };
type Light = { at: number; size: number; bright?: boolean };

const SKY_RING: Curve = { from: [-4, 30], bend: [50, 47], to: [104, 25] };
const LIFE: Light[] = [
  { at: 0.13, size: 0.7 },
  { at: 0.3, size: 0.85 },
  { at: 0.47, size: 0.75 },
  { at: 0.66, size: 1.5, bright: true },
  { at: 0.84, size: 0.8 },
];

// The same curve as the top edge of a section: the ground of the next part of the page.
const HORIZON: Curve = { from: [0, 18], bend: [50, 160], to: [100, 4] };
const THREE: Light[] = [
  { at: 0.2, size: 0.8 },
  { at: 0.5, size: 0.8 },
  { at: 0.8, size: 0.8 },
];

function onCurve(c: Curve, t: number) {
  const p = (i: 0 | 1) => (1 - t) ** 2 * c.from[i] + 2 * (1 - t) * t * c.bend[i] + t ** 2 * c.to[i];
  return { left: `${p(0).toFixed(2)}%`, top: `${p(1).toFixed(2)}%` };
}

const path = (c: Curve) => `M ${c.from.join(" ")} Q ${c.bend.join(" ")} ${c.to.join(" ")}`;

function Lights({ curve, lights }: { curve: Curve; lights: Light[] }) {
  return lights.map((l, i) => (
    <span
      key={l.at}
      className={l.bright ? "light light-bright" : "light"}
      style={{ ...onCurve(curve, l.at), "--size": l.size, "--order": i } as CSSProperties}
    />
  ));
}

function SkyRing() {
  return (
    <div className="ring" aria-hidden="true">
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" focusable="false">
        <path d={path(SKY_RING)} vectorEffect="non-scaling-stroke" />
      </svg>
      <Lights curve={SKY_RING} lights={LIFE} />
    </div>
  );
}

/** A section's curved top edge. With lights, the ring is drawn along it. */
function Horizon({ lights }: { lights?: Light[] }) {
  return (
    <div className="horizon" aria-hidden="true">
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" focusable="false">
        <path className="horizon-ground" d={`${path(HORIZON)} V 101 H 0 Z`} />
        {lights && <path className="horizon-ring" d={path(HORIZON)} pathLength={1} vectorEffect="non-scaling-stroke" />}
      </svg>
      {lights && <Lights curve={HORIZON} lights={lights} />}
    </div>
  );
}

export default function Page() {
  const c = en;
  return (
    <>
      <div className="journey">
      <header className="hero">
        <Sky scene="hero" />
        {/* With JavaScript off: a finished still of the same sky, and the ring drawn in place. */}
        <noscript>
          <picture className="sky-still">
            <source media="(max-aspect-ratio: 4/5)" type="image/webp" srcSet="/sky/tall.webp" />
            <source media="(max-aspect-ratio: 4/5)" srcSet="/sky/tall.jpg" />
            <source type="image/webp" srcSet="/sky/wide.webp" />
            <img src="/sky/wide.jpg" alt="" width={2000} height={1300} />
          </picture>
          <SkyRing />
        </noscript>

        <div className="hero-words wrap">
          <h1>
            <RevealWords text={c.hero.name} load={250} />
          </h1>
          <Reveal load={1100}>
            <p className="hero-sentence">{c.hero.sentence}</p>
          </Reveal>
          <Reveal load={1500} wrap className="action">
            <>
              <PressLink href={c.download.url}>{c.download.label}</PressLink>
              <span className="action-note">{c.hero.note}</span>
            </>
          </Reveal>
        </div>

        {/* The rest of the held scene. Hidden unless the live sky is running. */}
        <p className="stage stage-one">{c.journey.one}</p>
        <p className="stage stage-two">{c.journey.two}</p>
      </header>
      </div>

      <main>
        <section className="first wrap pair" aria-labelledby="sky-heading">
          <div className="pair-words">
            <Reveal>
              <h2 id="sky-heading">{c.sky.heading}</h2>
            </Reveal>
            {c.sky.body.map((p, i) => (
              <Reveal key={p} order={i + 1}>
                <p>{p}</p>
              </Reveal>
            ))}
          </div>
          <Reveal order={1} wrap className="shot-wrap lamp">
            <Shot name="sky" content={c} sizes="(min-width: 760px) 340px, 72vw" />
          </Reveal>
        </section>

        <section className="band" aria-labelledby="steps-heading">
          <Horizon lights={THREE} />
          <div className="wrap">
            <Reveal>
              <h2 id="steps-heading">{c.steps.heading}</h2>
            </Reveal>
            <ol className="steps">
              {c.steps.items.map((step, i) => (
                <li key={step.title}>
                  <Reveal order={i}>
                    <h3>{step.title}</h3>
                  </Reveal>
                  <Reveal order={i + 1}>
                    <p>{step.body}</p>
                  </Reveal>
                  <Reveal order={i + 2} wrap className="shot-wrap">
                    <Shot name={step.shot} content={c} sizes="(min-width: 760px) 300px, 72vw" />
                  </Reveal>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="words wrap" aria-labelledby="words-heading">
          <div className="words-intro">
            <Reveal>
              <h2 id="words-heading">{c.words.heading}</h2>
            </Reveal>
            <Reveal order={1}>
              <p>{c.words.body}</p>
            </Reveal>
          </div>
          <Reveal order={2} wrap className="specimen">
            <>
              <p className="specimen-text">
                {c.words.sample.map((part, i) =>
                  typeof part === "string" ? (
                    <span key={i}>{part} </span>
                  ) : (
                    <label key={i} className="cut">
                      <input type="checkbox" defaultChecked aria-label={`${c.words.leaveOut} “${part.cut}”`} />
                      <span>{part.cut}</span>{" "}
                    </label>
                  ),
                )}
              </p>
              <p className="specimen-note">
                <span className="specimen-count">{c.words.count} </span>
                {c.words.hint}
              </p>
            </>
          </Reveal>
        </section>

        <section className="band promises" aria-labelledby="promises-heading">
          <Horizon />
          <div className="wrap">
            <Reveal>
              <h2 id="promises-heading">{c.promises.heading}</h2>
            </Reveal>
            <ul className="litany">
              {c.promises.items.map((item) => (
                <li key={item.title}>
                  <Reveal>
                    <h3>{item.title}</h3>
                  </Reveal>
                  <Reveal order={1}>
                    <p>{item.body}</p>
                  </Reveal>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section className="wrap pair pair-flipped" aria-labelledby="share-heading">
          <div className="pair-words">
            <Reveal>
              <h2 id="share-heading">{c.share.heading}</h2>
            </Reveal>
            <Reveal order={1}>
              <p>{c.share.body}</p>
            </Reveal>
            <Reveal order={2}>
              <p className="aside">{c.share.note}</p>
            </Reveal>
          </div>
          <Reveal order={1} wrap className="shot-wrap">
            <Shot name="sharing" content={c} sizes="(min-width: 760px) 340px, 72vw" />
          </Reveal>
        </section>

        <section className="close" aria-labelledby="close-heading">
          <Sky scene="close" />
          <noscript>
            <picture className="sky-still">
              <source type="image/webp" srcSet="/sky/close.webp" />
              <img src="/sky/close.jpg" alt="" width={2000} height={1400} />
            </picture>
            <SkyRing />
          </noscript>
          <div className="close-words wrap">
            <Reveal wrap>
              <AppIcon content={c} />
            </Reveal>
            <Reveal order={1}>
              <h2 id="close-heading">{c.close.heading}</h2>
            </Reveal>
            <Reveal order={2} wrap className="action">
              <>
                <PressLink href={c.download.url}>{c.download.label}</PressLink>
                <span className="action-note">{c.close.note}</span>
              </>
            </Reveal>
          </div>
        </section>
      </main>

      <Footer content={c} />
    </>
  );
}
