import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { en } from "./content";
import "./globals.css";

// Newsreader, the app's typeface, served from this site. Nothing is fetched from anyone else.
const newsreader = localFont({
  src: [
    { path: "./fonts/newsreader-roman.woff2", style: "normal", weight: "300 600" },
    { path: "./fonts/newsreader-italic.woff2", style: "italic", weight: "300 600" },
  ],
  variable: "--font-newsreader",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://uponthyhead.app"),
  title: en.meta.title,
  description: en.meta.description,
  alternates: { canonical: "/" },
  openGraph: {
    title: en.meta.title,
    description: en.meta.description,
    url: "/",
    siteName: en.meta.title,
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#0B0907",
  colorScheme: "dark",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang={en.lang} className={newsreader.variable}>
      <body>
        {/* Without JavaScript nothing animates, so nothing may wait to be revealed. */}
        <noscript>
          <style>{"[data-reveal],[data-reveal] *{opacity:1!important;transform:none!important;filter:none!important}"}</style>
        </noscript>
        {children}
      </body>
    </html>
  );
}
