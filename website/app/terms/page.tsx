import type { Metadata } from "next";
import { en } from "../content";
import { PlainPage } from "../plain-page";

export const metadata: Metadata = {
  title: `${en.terms.title} · ${en.meta.title}`,
  description: en.terms.description,
  alternates: { canonical: "/terms" },
};

export default function Page() {
  return <PlainPage content={en} page={en.terms} />;
}
