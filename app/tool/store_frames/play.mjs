// Google Play's own graphics, into design/store/play/: the feature graphic in each language
// (feature-en.png, feature-es.png, 1024 x 500) and the icon (icon-512.png).
//
//   node tool/store_frames/play.mjs
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT ?? `${process.env.HOME}/.npm/_npx/e41f203b7505f1fb/node_modules/playwright`);
const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '../../../design/store/play');
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  args: ['--allow-file-access-from-files'],
});
for (const lang of ['en', 'es']) {
  const page = await browser.newPage({ viewport: { width: 1024, height: 500 } });
  await page.goto(`file://${here}/feature.html?lang=${lang}`);
  await page.waitForFunction('window.ready === true', null, { timeout: 30000 });
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(out, `feature-${lang}.png`), omitBackground: false });
  await page.close();
  console.log(`feature-${lang}.png`);
}
await browser.close();
// the icon, as the App Store has it, at Play's size
execFileSync('magick', [path.resolve(here, '../../../design/icon/final/icon-1024.png'), '-resize', '512x512', path.join(out, 'icon-512.png')]);
console.log('icon-512.png');
