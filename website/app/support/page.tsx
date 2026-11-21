import type { Metadata } from "next";
import { en } from "../content";
import { PlainPage } from "../plain-page";

export const metadata: Metadata = {
  title: `${en.support.title} · ${en.meta.title}`,
  description: en.support.description,
  alternates: { canonical: "/support" },
};

export default function Page() {
  return <PlainPage content={en} page={en.support} />;
}
