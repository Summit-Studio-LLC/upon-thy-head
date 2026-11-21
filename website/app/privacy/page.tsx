import type { Metadata } from "next";
import { en } from "../content";
import { PlainPage } from "../plain-page";

export const metadata: Metadata = {
  title: `${en.privacy.title} · ${en.meta.title}`,
  description: en.privacy.description,
  alternates: { canonical: "/privacy" },
};

export default function Page() {
  return <PlainPage content={en} page={en.privacy} />;
}
