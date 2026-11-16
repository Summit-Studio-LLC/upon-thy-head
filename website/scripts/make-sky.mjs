// Makes everything the sky needs, from the app's own Milky Way map and star catalogue, in the
// Lamplight tint. Reads from ../design/prototype/src (never writes there).
// Usage: node scripts/make-sky.mjs
//
// For each view it writes to public/sky/:
//   <name>-glow.*  the Milky Way and the very faintest stars; the page draws the rest live over it
//   <name>.*       a finished still with every star, shown when JavaScript is off
// and for each scene, <scene>.stars: the bright stars (6 bytes each: ra u16, dec i16, mag u8, B-V u8).
// The cameras are written to app/sky-views.json so the live sky lines up with the pictures.
//
// Sources: Milky Way from NASA/GSFC Scientific Visualization Studio, Deep Star Maps 2020 (public
// domain); stars from the HYG Database v4.1 by David Nash (CC BY-SA 4.0).
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';

const here = path.dirname(new URL(import.meta.url).pathname);
const SRC = path.resolve(here, '../../design/prototype/src');
const OUT = path.resolve(here, '../public/sky');

// Where each camera looks (hours, degrees), how far it is rolled, and how wide it sees.
const VIEWS = {
  wide: { w: 2000, h: 1300, ra: 19.3, dec: 36, roll: 58, fov: 78 },
  tall: { w: 1000, h: 1800, ra: 20.1, dec: 34, roll: 8, fov: 44 },
  close: { w: 2000, h: 1400, ra: 17.95, dec: -24, roll: -62, fov: 74 }, // toward the centre of the galaxy
};
const SCENES = { hero: { views: ['wide', 'tall'], cone: 60 }, close: { views: ['close'], cone: 56 } };
const OVERSIZE = 1.3; // the glow is drawn this much wider than the still, leaving room to move
const LIVE_MAG = 9.6; // stars at least this bright are drawn live, sharp at any screen density
const REF = 1400; // star sizes are tuned at this picture width
const TINT = [1.07, 0.98, 0.85]; // Lamplight, from app/lib/theme.dart
const GROUND = [11, 9, 7];

const map = await sharp(path.join(SRC, 'mw8k_c.jpg'), { limitInputPixels: false }).raw().toBuffer({ resolveWithObject: true });
const MW = map.data, MWW = map.info.width, MWH = map.info.height;
const stars = Buffer.from(fs.readFileSync(path.join(SRC, 'stars.b64'), 'utf8'), 'base64');

const rad = Math.PI / 180;
const vec = (ra, dec) => [Math.cos(dec) * Math.cos(ra), Math.cos(dec) * Math.sin(ra), Math.sin(dec)];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const norm = (a) => { const l = Math.hypot(...a); return a.map((x) => x / l); };
const starAt = (i) => ({
  ra: (stars.readUInt16LE(i) / 65536) * 2 * Math.PI,
  dec: (stars.readInt16LE(i + 2) / 32767) * (Math.PI / 2),
  mag: stars[i + 4] / 20 - 2,
  bv: stars[i + 5] / 100 - 0.5,
});

function camera(V) {
  const fwd = vec(V.ra * 15 * rad, V.dec * rad);
  let right = norm(cross(fwd, [0, 0, 1])); // east is to the left, as the sky is seen from below
  let up = cross(right, fwd);
  const cr = Math.cos(V.roll * rad), sr = Math.sin(V.roll * rad);
  [right, up] = [right.map((x, i) => x * cr + up[i] * sr), up.map((x, i) => x * cr - right[i] * sr)];
  return { fwd, right, up };
}

function sample(u, v, c) {
  const x = ((u % 1) + 1) % 1 * MWW - 0.5, y = Math.min(MWH - 1.001, Math.max(0, v * MWH - 0.5));
  const x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
  const xa = (x0 + MWW) % MWW, xb = (x0 + 1) % MWW;
  const p = (xx, yy) => MW[(yy * MWW + xx) * 3 + c];
  return (p(xa, y0) * (1 - fx) + p(xb, y0) * fx) * (1 - fy) + (p(xa, y0 + 1) * (1 - fx) + p(xb, y0 + 1) * fx) * fy;
}

/** Draws one picture. `halfTan` is the tangent of half the horizontal field of view. */
function draw(V, halfTan, starScale, keep) {
  const { w, h } = V, f = (w / 2) / halfTan, { fwd, right, up } = camera(V);
  const img = new Float32Array(w * h * 3);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const dx = (x + 0.5 - w / 2) / f, dy = (h / 2 - y - 0.5) / f;
    const d = norm([fwd[0] + right[0] * dx + up[0] * dy, fwd[1] + right[1] * dx + up[1] * dy, fwd[2] + right[2] * dx + up[2] * dy]);
    const u = 0.5 - Math.atan2(d[1], d[0]) / (2 * Math.PI), v = 0.5 - Math.asin(d[2]) / Math.PI;
    const o = (y * w + x) * 3;
    for (let c = 0; c < 3; c++) img[o + c] = GROUND[c] / 255 * 0.55 + Math.pow(sample(u, v, c) / 255, 1.25) * 1.05 * TINT[c];
  }
  // Stars: a small soft point each, brighter and slightly larger with magnitude.
  for (let i = 0; i < stars.length; i += 6) {
    const { ra, dec, mag, bv } = starAt(i);
    if (!keep(mag)) continue;
    const s = vec(ra, dec), z = dot(s, fwd);
    if (z < 0.2) continue;
    const px = w / 2 + (dot(s, right) / z) * f, py = h / 2 - (dot(s, up) / z) * f;
    if (px < -6 || py < -6 || px > w + 6 || py > h + 6) continue;
    const flux = Math.pow(10, -0.4 * (mag - 6.2)) * 0.55;
    const base = 0.55 + Math.min(2.2, Math.sqrt(flux) * 0.2);
    const sigma = base * starScale;
    const t = Math.max(0, Math.min(1, (bv + 0.3) / 1.9)); // blue-white to warm
    const col = [1.0, 0.985 - 0.09 * t, (1.0 - 0.3 * t) * 0.97];
    const r = Math.ceil(sigma * 3.2), amp = Math.min(1.6, flux / (base * base * 4.5));
    for (let yy = Math.floor(py) - r; yy <= Math.floor(py) + r; yy++) for (let xx = Math.floor(px) - r; xx <= Math.floor(px) + r; xx++) {
      if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
      const g = amp * Math.exp(-((xx + 0.5 - px) ** 2 + (yy + 0.5 - py) ** 2) / (2 * sigma * sigma));
      if (g < 0.004) continue;
      const o = (yy * w + xx) * 3;
      for (let c = 0; c < 3; c++) img[o + c] += g * col[c];
    }
  }
  const out = Buffer.alloc(w * h * 3);
  for (let i = 0; i < out.length; i++) { const x = img[i]; out[i] = Math.round(255 * (x > 1 ? 1 : x)); }
  return sharp(out, { raw: { width: w, height: h, channels: 3 } });
}

const kb = (file) => `${path.basename(file)} ${Math.round(fs.statSync(file).size / 1024)}KB`;
for (const f of fs.readdirSync(OUT)) fs.rmSync(path.join(OUT, f));

for (const [name, V] of Object.entries(VIEWS)) {
  const halfTan = Math.tan((V.fov * rad) / 2), scale = V.w / REF, files = [];
  // Drawn larger by the same amount, so it is as sharp as the still once enlarged on the page.
  const big = { ...V, w: Math.round(V.w * OVERSIZE), h: Math.round(V.h * OVERSIZE) };
  const glow = draw(big, halfTan * OVERSIZE, scale, (mag) => mag > LIVE_MAG);
  for (const [ext, make] of [['avif', (s) => s.avif({ quality: 46, effort: 7 })], ['webp', (s) => s.webp({ quality: 62, effort: 6 })], ['jpg', (s) => s.jpeg({ quality: 68, mozjpeg: true })]]) {
    const file = path.join(OUT, `${name}-glow.${ext}`); await make(glow.clone().sharpen({ sigma: 1.1, m1: 0.6, m2: 1.4 })).toFile(file); files.push(file);
  }
  const still = draw(V, halfTan, scale, () => true);
  for (const [ext, make] of [['webp', (s) => s.webp({ quality: 62, effort: 6 })], ['jpg', (s) => s.jpeg({ quality: 68, mozjpeg: true })]]) {
    const file = path.join(OUT, `${name}.${ext}`); await make(still.clone()).toFile(file); files.push(file);
  }
  console.log(files.map(kb).join(', '));
}

for (const [scene, S] of Object.entries(SCENES)) {
  const { fwd } = camera(VIEWS[S.views[0]]), limit = Math.cos(S.cone * rad), picked = [];
  for (let i = 0; i < stars.length; i += 6) {
    const { ra, dec, mag } = starAt(i);
    if (mag <= LIVE_MAG && dot(vec(ra, dec), fwd) > limit) picked.push(stars.subarray(i, i + 6));
  }
  const file = path.join(OUT, `${scene}.stars`);
  fs.writeFileSync(file, Buffer.concat(picked));
  console.log(kb(file), picked.length, 'stars');
}

fs.writeFileSync(path.resolve(here, '../app/sky-views.json'), JSON.stringify({ oversize: OVERSIZE, ref: REF, views: VIEWS }, null, 2) + '\n');
