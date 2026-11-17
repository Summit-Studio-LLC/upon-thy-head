// A blessing link opened in a real browser (Chrome, through Playwright), as the person it was sent
// to would open it: prints what the page shows, as one line of JSON. For tool/link_acceptance.sh.
//
//   node tool/link_web.mjs <link> [screenshot.png]
//
// The app's test build names the logging proxy in its links (tool/link_proxy.py); the browser goes
// to the website itself, so the proxy's log holds the app's requests only.
import { createRequire } from "node:module";

const [link, shot] = process.argv.slice(2);
const site = process.env.WEBSITE ?? "http://127.0.0.1:4319";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT ?? `${process.env.HOME}/.npm/_npx/e41f203b7505f1fb/node_modules/playwright`);

const url = new URL(link);
const target = new URL(site);
url.protocol = target.protocol;
url.host = target.host;

const browser = await chromium.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" });
try {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: "en-US" });
  const p = await context.newPage();
  await p.goto(url.toString());
  await p.waitForFunction(() => ["open", "key", "newer", "gone"].includes(document.body.dataset.state), null, { timeout: 15000 });
  const text = async (s) => ((await p.$(s)) ? (await p.textContent(s)) ?? "" : "");
  const out = {
    state: await p.evaluate(() => document.body.dataset.state),
    h1: await text("h1"),
    title: await text(".title"),
    from: await text(".from"),
    given: await text(".given"),
    words: await p.$$eval(".words p", (ps) => ps.map((x) => x.textContent)),
    notes: await text(".notes"),
  };
  if (shot) await p.screenshot({ path: shot, fullPage: false });
  console.log(JSON.stringify(out));
} finally {
  await browser.close();
}
