import { wordsFor } from "../../../public/shared/words.js";

// The page a shared link opens. It is one small document with no inline script and no library:
// the browser loads /shared/page.js, which fetches the locked copy and opens it there. The server
// never has the key (it is the part of the address after "#", which browsers do not send), so
// this document is the same for every blessing.

const CSP = [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  "font-src 'self'",
  "img-src 'self'",
  "connect-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

export async function GET(request: Request) {
  const w = wordsFor((request.headers.get("accept-language") ?? "").split(",").map((l) => l.split(";")[0]));
  const html = `<!doctype html>
<html lang="${w.lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow, noarchive">
<meta name="referrer" content="no-referrer">
<meta name="theme-color" content="#0B0907">
<meta name="color-scheme" content="dark">
<title>${esc(w.pageTitle)} · ${esc(w.brand)}</title>
<meta property="og:title" content="${esc(w.pageTitle)}">
<meta property="og:site_name" content="uponthyhead.app">
<link rel="icon" href="/icon.png" type="image/png">
<link rel="apple-touch-icon" href="/apple-icon.png">
<link rel="stylesheet" href="/shared/page.css">
<script type="module" src="/shared/page.js"></script>
</head>
<body>
<div class="sky" aria-hidden="true">
<picture>
<source media="(min-width: 48rem)" type="image/webp" srcset="/sky/wide.webp">
<source media="(min-width: 48rem)" srcset="/sky/wide.jpg">
<source type="image/webp" srcset="/sky/tall.webp">
<img src="/sky/tall.jpg" alt="" width="1000" height="1800">
</picture>
<span class="sky-light"></span>
</div>
<div class="column">
<a class="brand" href="/" rel="noreferrer"><img src="/app-icon.png" alt="" width="36" height="36">${esc(w.brand)}</a>
<main id="main" aria-live="polite"></main>
<noscript><h1>${esc(w.noScript.title)}</h1><p>${esc(w.noScript.body)}</p></noscript>
</div>
<div class="keep" id="keep" hidden></div>
</body>
</html>
`;
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": CSP,
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Robots-Tag": "noindex, nofollow, noarchive",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Permissions-Policy": "camera=(), microphone=(), geolocation=(), interest-cohort=()",
      Vary: "Accept-Language",
    },
  });
}
