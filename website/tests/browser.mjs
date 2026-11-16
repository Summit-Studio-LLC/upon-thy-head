// The real thing in real browsers (Chromium and WebKit): a link made by tests/phone.mjs is opened,
// read, stopped, and opened wrongly, while every request the page makes is captured to show that
// none carries the key. Needs the site running with local storage:
//   LINKS_LOCAL_DIR=.data/links pnpm start -p 4319      then      node tests/browser.mjs [origin] [screenshot folder]
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import fs from "node:fs";
import { lock, sample, share, stop } from "./phone.mjs";

const origin = process.argv[2] ?? "http://localhost:4319";
const shots = process.argv[3];
const require = createRequire(import.meta.url);
const playwrightPath = process.env.PLAYWRIGHT ?? `${process.env.HOME}/.npm/_npx/e41f203b7505f1fb/node_modules/playwright`;
const { chromium, webkit } = require(playwrightPath);
if (shots) fs.mkdirSync(shots, { recursive: true });

const long = () => {
  const sentence = "Bendigo tu corazón con paz, y que la fe te acompañe día y noche 🌟. ";
  const words = Array.from({ length: 180 }, (_, i) => sentence + (i % 6 === 5 ? "\n\n" : "")).join("").trim();
  return { ...sample(), title: "Una bendición larga", language: "es", words, changes: [] };
};

let checks = 0;
const ok = (value, what) => {
  assert.ok(value, what);
  checks++;
};

async function run(name, type) {
  const browser = await type.launch(type === chromium ? { executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" } : {});
  const made = await share(origin);
  const requests = [];
  const problems = [];

  async function page(options = {}) {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: "en-US", ...options });
    const p = await context.newPage();
    p.on("request", (r) => requests.push({ url: r.url(), headers: JSON.stringify(r.headers()), body: r.postData() ?? "" }));
    // When taking screenshots, Playwright's WebKit injects a style of its own, which the page's
    // policy rightly refuses; that one message is not the page's. Without screenshots there is none.
    const expected = (text) => /status of (410|404|429)/.test(text) || (shots && /Refused to apply a stylesheet/.test(text));
    p.on("console", (m) => m.type() === "error" && !expected(m.text()) && problems.push(m.text()));
    p.on("pageerror", (e) => problems.push(String(e)));
    return p;
  }
  const shot = async (p, file) => shots && p.screenshot({ path: `${shots}/${name}-${file}.png` });
  const state = (p, s) => p.waitForSelector(`body[data-state="${s}"]`, { timeout: 8000 });

  // 1. The blessing opens and shows the right words (English).
  let p = await page();
  const response = await p.goto(made.link);
  await state(p, "open");
  ok((await p.textContent(".title")) === "Comfort before surgery", "title");
  ok((await p.textContent(".from")) === "A blessing from Dad", "from");
  ok((await p.textContent(".given")) === "Tuesday, March 3, 2026 · For Emma", `date and recipient: ${await p.textContent(".given")}`);
  ok(/^Shared with you · until \w+ \d+$/.test(await p.textContent(".shared")), "until");
  const shown = await p.$$eval(".words p", (ps) => ps.map((x) => x.textContent));
  ok(shown.length === 2 && shown[0] === "Emma, I lay my hands upon your head, to give you a blessing of comfort.", `kept changes applied: ${shown[0]}`);
  ok(shown[1].includes("and, uh, He wants you"), "the restored change shows the spoken words");
  ok((await p.textContent(".notes")).includes("with 2 small changes"), "polished note");
  ok((await p.textContent("#keep")).includes("coming to iPhone and Android") && (await p.$$("#keep a")).length === 0, "coming soon, with no dead button");
  ok((await p.evaluate(() => location.href)) === made.link, "the address, with its key, is left as it came");
  ok((await p.context().cookies()).length === 0 && (await p.evaluate(() => localStorage.length + sessionStorage.length)) === 0, "no cookies, nothing stored");
  const h = response.headers();
  ok(h["cache-control"] === "no-store" && h["referrer-policy"] === "no-referrer" && /noindex/.test(h["x-robots-tag"]), "page headers");
  ok(/default-src 'none'/.test(h["content-security-policy"]) && !/unsafe/.test(h["content-security-policy"]), "strict content security policy");
  await shot(p, "en-phone");
  await p.setViewportSize({ width: 1440, height: 900 });
  await shot(p, "en-desktop");

  // Reloading works, because the key is still in the address.
  await p.reload();
  await state(p, "open");
  ok((await p.textContent(".title")) === "Comfort before surgery", "reload");
  await p.context().close();

  // 2. Spanish, by the browser's language.
  p = await page({ locale: "es-MX" });
  await p.goto(made.link);
  await state(p, "open");
  ok((await p.textContent(".from")) === "Una bendición de Dad", "es: from");
  ok((await p.textContent(".given")) === "martes, 3 de marzo de 2026 · Para Emma", `es: date: ${await p.textContent(".given")}`);
  ok(/^Compartida contigo · hasta el \d+ de \w+$/.test(await p.textContent(".shared")), `es: until: ${await p.textContent(".shared")}`);
  ok((await p.getAttribute("html", "lang")) === "es", "es: lang");
  await shot(p, "es-phone");
  await p.context().close();

  // 3. A long blessing: 2,500 words, accents, an emoji.
  const record = long();
  const big = await share(origin, record);
  p = await page();
  await p.goto(big.link);
  await state(p, "open");
  const all = (await p.$$eval(".words p", (ps) => ps.map((x) => x.textContent))).join("\n\n");
  ok(all === record.words.split(/\n\s*\n/).map((s) => s.trim()).join("\n\n"), "every word of the long blessing, in order");
  ok(all.split(/\s+/).length >= 2500 && all.includes("🌟") && all.includes("corazón"), "2,500 words with accents and the emoji");
  ok((await p.evaluate(() => document.documentElement.scrollWidth - innerWidth)) <= 0, "no sideways scroll");
  await shot(p, "long-phone");
  await p.context().close();

  // 4. A wrong key, and no key.
  p = await page();
  await p.goto(`${origin}/b/${made.id}#${Buffer.alloc(32, 7).toString("base64url")}`);
  await state(p, "key");
  ok((await p.textContent("h1")) === "This link is not complete." && !(await p.textContent("body")).includes("Emma"), "wrong key");
  await shot(p, "wrong-key");
  await p.goto(`${origin}/b/${made.id}`);
  await state(p, "key");
  ok(true, "no key");
  await p.context().close();

  // 5. Made by a newer version.
  const newer = await share(origin, { ...sample(), version: 2 });
  p = await page();
  await p.goto(newer.link);
  await state(p, "newer");
  ok((await p.textContent("h1")).includes("newer version"), "newer");
  await shot(p, "newer");
  await p.context().close();

  // 6. Stopped: the copy is erased and the page says so.
  ok((await stop(origin, made)).status === 204, "stop");
  p = await page();
  await p.goto(made.link);
  await state(p, "gone");
  ok((await p.textContent("h1")) === "This link has stopped working.", "stopped page");
  ok((await p.isHidden("#keep")), "nothing to keep on a stopped link");
  await shot(p, "stopped-phone");
  await p.setViewportSize({ width: 1440, height: 900 });
  await shot(p, "stopped-desktop");
  await p.context().close();
  p = await page({ locale: "es-ES" });
  await p.goto(made.link);
  await state(p, "gone");
  ok((await p.textContent("h1")) === "Este enlace dejó de funcionar.", "es: stopped page");
  await shot(p, "es-stopped");
  await p.context().close();

  // 7. Without JavaScript: it says plainly why it is needed.
  p = await page({ javaScriptEnabled: false });
  await p.goto(big.link);
  ok((await p.textContent("noscript h1")) === "This page needs JavaScript to unlock the blessing.", "no JavaScript");
  ok(!(await p.textContent("body")).includes("Bendigo"), "no words without JavaScript");
  await shot(p, "no-javascript");
  await p.context().close();

  // 8. The switch: with a store address, the button appears and goes there.
  p = await page();
  await p.route("**/shared/stores.js", (r) => r.fulfill({ contentType: "text/javascript", body: 'export const STORES = { appStore: "https://apps.apple.com/app/id1", googlePlay: "" };' }));
  await p.goto(big.link);
  await state(p, "open");
  ok((await p.getAttribute("#keep a", "href")) === "https://apps.apple.com/app/id1" && (await p.textContent("#keep a")) === "Keep it in Upon Thy Head", "the store switch");
  await shot(p, "with-store-button");
  await p.context().close();

  // 9. The key never left the page: not in any address, header or body of any request.
  const keys = [made.key, big.key, newer.key, Buffer.alloc(32, 7).toString("base64url")];
  const leaks = requests.filter((r) => keys.some((k) => r.url.includes(k) || r.headers.includes(k) || r.body.includes(k) || r.url.includes("#")));
  ok(leaks.length === 0, `requests carrying the key: ${JSON.stringify(leaks)}`);
  const hosts = new Set(requests.map((r) => new URL(r.url).host));
  ok(hosts.size === 1 && hosts.has(new URL(origin).host), `only this site was asked for anything: ${[...hosts]}`);
  const asked = [...new Set(requests.map((r) => new URL(r.url).pathname.replace(/\/[A-Za-z0-9_-]{22}$/, "/<id>")))].sort();
  ok(problems.length === 0, `browser errors: ${problems.join(" | ")}`);
  await browser.close();
  console.log(`${name}: ${requests.length} requests, none with the key. Paths asked for: ${asked.join(" ")}`);
}

await run("chromium", chromium);
await run("webkit", webkit);

// The service's own answers.
const made = await share(origin);
const got = await fetch(`${origin}/api/b/${made.id}`);
ok(got.headers.get("cache-control") === "no-store" && got.headers.get("x-content-type-options") === "nosniff" && got.headers.get("content-type") === "application/octet-stream" && !got.headers.get("access-control-allow-origin") && !got.headers.get("set-cookie"), "read headers");
const big = await fetch(`${origin}/api/b`, { method: "POST", headers: { "content-type": "application/octet-stream" }, body: Buffer.alloc(65537, 1) });
ok(big.status === 413, "too big over the wire");
const aasa = await fetch(`${origin}/.well-known/apple-app-site-association`, { redirect: "manual" });
ok(aasa.status === 200 && aasa.headers.get("content-type") === "application/json" && (await aasa.json()).applinks.details[0].components[0]["/"] === "/b/*", "apple-app-site-association");
const links = await fetch(`${origin}/.well-known/assetlinks.json`, { redirect: "manual" });
ok(links.status === 200 && links.headers.get("content-type") === "application/json" && JSON.stringify(await links.json()) === "[]", "assetlinks.json");
ok((await fetch(`${origin}/api/sweep`)).status === 401, "the clean-up cannot be run without its secret");
// What is on disk for a link: no key, no title, no words.
const dir = process.env.LINKS_LOCAL_DIR;
if (dir) {
  const kept = fs.readFileSync(`${dir}/${made.id}.copy`, "utf8");
  ok(!kept.includes(made.key) && !kept.includes(made.stop) && !/Comfort|Emma|Dad/.test(Buffer.from(JSON.parse(kept).c, "base64").toString("latin1")), "what is kept holds no key, no stop token and no readable word");
  ok(Object.keys(JSON.parse(kept)).sort().join() === "c,e,s", "three things are kept");
}
console.log(`${checks} checks passed`);
