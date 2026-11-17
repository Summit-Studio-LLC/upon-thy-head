// Pairs of pictures side by side, each pair captioned, saved as one PNG (Chrome through Playwright).
//
//   node tool/side_by_side.mjs <out.png> "<caption>" <left.png> <right.png> ["<caption>" <left> <right>]…
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

const [out, ...rest] = process.argv.slice(2);
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT ?? `${process.env.HOME}/.npm/_npx/e41f203b7505f1fb/node_modules/playwright`);
const img = (f) => `data:image/png;base64,${fs.readFileSync(f).toString("base64")}`;
let rows = "";
for (let i = 0; i + 2 < rest.length + 1; i += 3) {
  const [caption, a, b] = rest.slice(i, i + 3);
  rows += `<section><h2>${caption}</h2><div class="pair">
    <figure><img src="${img(a)}"><figcaption>The drawing · ${path.basename(a)}</figcaption></figure>
    <figure><img src="${img(b)}"><figcaption>The app · ${path.basename(b)}</figcaption></figure></div></section>`;
}
const html = `<!doctype html><meta charset="utf-8"><style>
  body{margin:0;padding:32px;background:#f4f1ea;font:15px -apple-system,system-ui,sans-serif;color:#222}
  h2{font-weight:500;font-size:18px;margin:0 0 12px} section{margin-bottom:36px}
  .pair{display:flex;gap:32px;align-items:flex-start} figure{margin:0}
  img{height:760px;border-radius:24px;box-shadow:0 2px 12px #0002;display:block} figcaption{margin-top:8px;color:#666}
</style><body>${rows}</body>`;
const browser = await chromium.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" });
const p = await browser.newPage({ viewport: { width: 900, height: 900 }, deviceScaleFactor: 1 });
await p.setContent(html);
await p.screenshot({ path: out, fullPage: true });
await browser.close();
console.log(out);
