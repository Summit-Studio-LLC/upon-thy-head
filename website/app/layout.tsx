import type { Metadata, Viewport } from "next";
import { Manrope } from "next/font/google";
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

// Manrope, Summit Studio's typeface, for the footer. Downloaded when the site is built and served
// from this site; a visitor's browser never asks Google for it.
const manrope = Manrope({ variable: "--font-manrope", subsets: ["latin"], display: "swap", preload: false });

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
    <html lang={en.lang} className={`${newsreader.variable} ${manrope.variable}`}>
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
