"use client";

import type { ReactElement } from "react";
import { Button } from "@animate-ui/react/primitives/buttons/button";
import { Effect } from "@animate-ui/react/primitives/effects/effect";
import { SplittingText } from "@animate-ui/react/primitives/texts/splitting";

// How the words arrive. The shape is the "Texts reveal" recipe from transitions.dev (a short rise,
// a little blur, a fade, on the app's own curve), played by Animate UI's primitives and slowed to
// suit this page. With Reduce Motion on, Animate UI drops the travel and keeps a plain fade.
const EASE = [0.22, 1, 0.36, 1] as const;
const RISE = 12; // px
const BLUR = 3; // px
const STAGGER = 110; // ms between neighbours
const DURATION = { load: 1.6, scroll: 1.1 }; // seconds

type RevealProps = {
  children: ReactElement;
  /** Position among its neighbours; each step waits a little longer. */
  order?: number;
  /** Play as the page opens, after this many milliseconds, instead of when scrolled into view. */
  load?: number;
  /** Wrap the child in a div instead of animating the child itself (for components). */
  wrap?: boolean;
  className?: string;
};

export function Reveal({ children, order = 0, load, wrap = false, className }: RevealProps) {
  const onLoad = load !== undefined;
  return (
    <Effect
      asChild={!wrap}
      data-reveal=""
      className={className}
      fade
      blur={{ initialBlur: BLUR }}
      slide={{ direction: "up", offset: RISE }}
      inView={!onLoad}
      inViewOnce
      inViewMargin="0px 0px -8% 0px"
      delay={(load ?? 0) + order * STAGGER}
      transition={{ duration: onLoad ? DURATION.load : DURATION.scroll, ease: EASE }}
    >
      {children}
    </Effect>
  );
}

/** The name, arriving one word at a time, as the lights do. */
export function RevealWords({ text, load = 0 }: { text: string; load?: number }) {
  return (
    <SplittingText
      data-reveal=""
      type="words"
      text={text}
      delay={load}
      stagger={0.24}
      initial={{ y: RISE, opacity: 0, filter: `blur(${BLUR * 2}px)` }}
      animate={{ y: 0, opacity: 1, filter: "blur(0px)" }}
      transition={{ duration: DURATION.load, ease: EASE }}
    />
  );
}

/** The download link: it gives slightly under a press. */
export function PressLink({ href, children }: { href: string; children: string }) {
  // no address yet: the same shape, as words and not a link
  if (!href) return <span className="download download-soon">{children}</span>;
  return (
    <Button asChild hoverScale={1.02} tapScale={0.97}>
      <a className="download" href={href}>
        {children}
      </a>
    </Button>
  );
}
