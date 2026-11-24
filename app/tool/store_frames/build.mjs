// The store pictures, from the plain screenshots in design/store/<lang>/<device>/ (made by
// tool/store_shots.sh and tool/store_shots_android.sh) to the captioned frames in design/store/framed/<lang>/<device>/01.png … 07.png.
//
//   node tool/store_frames/build.mjs [en|es ...] [iphone|ipad|android ...]
//
// Needs Playwright and Google Chrome. PLAYWRIGHT can point at another copy of Playwright.
// Each set also gets one small picture of the whole row, beside it: framed/<lang>-<device>.jpg.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT ?? `${process.env.HOME}/.npm/_npx/e41f203b7505f1fb/node_modules/playwright`);
const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '../../../design/store/framed');
const args = process.argv.slice(2);
const pick = (all) => { const some = all.filter((a) => args.includes(a)); return some.length ? some : all; };

const browser = await chromium.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  args: ['--allow-file-access-from-files'],
});
for (const lang of pick(['en', 'es'])) {
  for (const device of pick(['iphone', 'ipad', 'android'])) {
    const dir = path.join(out, lang, device);
    fs.mkdirSync(dir, { recursive: true });
    const page = await browser.newPage({ viewport: { width: 1320, height: 2868 } });
    page.on('pageerror', (e) => { console.error(`${lang} ${device}: ${e.message}`); process.exitCode = 1; });
    await page.goto(`file://${here}/frames.html?lang=${lang}&device=${device}`);
    await page.waitForFunction('window.ready === true', null, { timeout: 30000 });
    const { FW, FH } = await page.evaluate('window.FRAME');
    await page.setViewportSize({ width: FW, height: FH });
    for (let i = 0; i < 7; i++) {
      await page.evaluate((x) => { document.getElementById('strip').style.transform = `translateX(${-x}px)`; }, i * FW);
      await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(dir, `0${i + 1}.png`) });
    }
    await page.close();
    // the whole row, small, as the store lays the pictures out
    const w = 300, gap = 14, h = Math.round((w * FH) / FW);
    const row = await browser.newPage({ viewport: { width: 7 * w + 8 * gap, height: h + 2 * gap } });
    const sheet = path.join(out, `${lang}-${device}.html`);
    fs.writeFileSync(sheet, `<body style="margin:0;background:#1c1c1e;display:flex;gap:${gap}px;padding:${gap}px">` +
      Array.from({ length: 7 }, (_, i) => `<img src="${lang}/${device}/0${i + 1}.png" style="width:${w}px;border-radius:${w * 0.05}px">`).join('') + '</body>');
    await row.goto(`file://${sheet}`);
    await row.waitForTimeout(600);
    await row.screenshot({ path: path.join(out, `${lang}-${device}.jpg`), type: 'jpeg', quality: 88 });
    await row.close();
    fs.rmSync(sheet);
    console.log(`${lang} ${device}: 7 pictures, ${FW}x${FH}`);
  }
}
await browser.close();
