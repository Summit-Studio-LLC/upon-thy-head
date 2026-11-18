"use client";

import { useEffect, useRef } from "react";
import data from "./sky-views.json";

// The living sky. The Milky Way is a picture (public/sky/*-glow.*). Over it, every star down to
// magnitude 9.6 is drawn live from the real catalogue, through the same camera that made the
// picture, so the stars are sharp on any screen and each can sit at its own depth: as the page
// scrolls the near ones travel far and the distant ones barely move.
//
// The ring of lights is drawn in the same space. It begins as the arc that crosses overhead and,
// as the page scrolls, draws away into a whole halo that turns.
//
// With JavaScript off, a finished still is shown instead (see page.tsx). With Reduce Motion on, the
// sky is drawn once and holds still.

type ViewName = keyof typeof data.views;
type Scene = "hero" | "close";

const SCENES: Record<Scene, { wide: ViewName; tall: ViewName }> = {
  hero: { wide: "wide", tall: "tall" },
  close: { wide: "close", tall: "close" },
};
const TALL = "(max-aspect-ratio: 4/5)";
const DEG = Math.PI / 180;

// The arc overhead: a circle on the sky, centred above the view so it sags across it.
const ARC_RADIUS = 75 * DEG;
const ARC_TILT = -2.5 * DEG;

// The lights. The first five are the ones seen on the arc (`at` runs 0 to 1 across the view); the
// rest sit farther round the ring (`round`, in radians from its nearest point) and are only seen
// once it has become a halo.
type Light = { at?: number; round?: number; size: number; newest?: boolean };
const LIGHTS: Light[] = [
  { at: 0.13, size: 0.7 },
  { at: 0.3, size: 0.85 },
  { at: 0.47, size: 0.75 },
  { at: 0.66, size: 1.5, newest: true },
  { at: 0.84, size: 0.8 },
  { round: 1.25, size: 0.75 },
  { round: 1.8, size: 0.9 },
  { round: 2.45, size: 0.7 },
  { round: 3.0, size: 0.85 },
  { round: -2.6, size: 0.75 },
  { round: -1.95, size: 0.9 },
  { round: -1.3, size: 0.7 },
];

const PROJECT = `
uniform float u_focal, u_scale;
uniform vec2 u_rot, u_half;
vec4 place(vec3 p, vec2 nudge, float zoom) {
  if (p.z < 0.1) return vec4(2.0, 2.0, 2.0, 1.0);
  vec2 q = vec2(p.x, -p.y) / p.z * u_focal * u_scale * zoom;
  q = vec2(q.x * u_rot.x - q.y * u_rot.y, q.x * u_rot.y + q.y * u_rot.x) + nudge;
  return vec4(q.x / u_half.x, -q.y / u_half.y, 0.0, 1.0);
}`;

// Light laid over the page. The canvas holds premultiplied colour, so a colour must carry a
// matching alpha: Safari throws away light that claims to be fully transparent.
const LIT = `
vec4 lit(vec3 c) {
  c = min(c, vec3(1.0));
  return vec4(c, max(c.r, max(c.g, c.b)));
}`;

const STAR_VS = `
attribute vec3 a_dir;
attribute vec2 a_mb;
uniform vec3 u_right, u_up, u_fwd;
uniform vec2 u_travel; // how far the nearest stars have moved, in px
uniform float u_sig, u_dpr, u_rush;
varying vec3 v_col;
varying float v_sig, v_size;
${PROJECT}
void main() {
  float mag = a_mb.x;
  // Depth: bright stars are near. A little scatter keeps the layers from reading as bands.
  float scatter = fract(sin(dot(a_dir.xy, vec2(12.9898, 78.233))) * 43758.5453);
  float depth = pow(clamp((9.6 - mag) / 8.6, 0.0, 1.0), 1.35) * 0.82 + scatter * 0.18;
  vec3 p = vec3(dot(a_dir, u_right), dot(a_dir, u_up), dot(a_dir, u_fwd));
  gl_Position = place(p, u_travel * (0.05 + 0.95 * depth), 1.0 + depth * u_rush);
  float flux = pow(10.0, -0.4 * (mag - 6.2)) * 0.55;
  float base = 0.55 + min(2.2, sqrt(flux) * 0.2);
  float want = base * u_sig;
  float sigma = max(want, 0.5) * u_dpr;
  float amp = min(1.6, flux / (base * base * 4.5)) * min(1.0, (want * want) / 0.25) * 1.25;
  float t = clamp((a_mb.y + 0.3) / 1.9, 0.0, 1.0);
  v_col = vec3(1.0, 0.985 - 0.09 * t, (1.0 - 0.3 * t) * 0.97) * amp;
  v_sig = sigma;
  v_size = max(2.0, sigma * 6.4);
  gl_PointSize = v_size;
}`;

const STAR_FS = `
precision mediump float;
${LIT}
varying vec3 v_col;
varying float v_sig, v_size;
void main() {
  vec2 d = (gl_PointCoord - 0.5) * v_size;
  gl_FragColor = lit(v_col * exp(-dot(d, d) / (2.0 * v_sig * v_sig)));
}`;

// A point on the ring: its centre, and the two arms that carry a point round it.
const RING = `
uniform vec3 u_c, u_a, u_b;
uniform vec2 u_ringNudge;
uniform float u_halo;
vec3 onRing(float th) { return u_c + u_a * cos(th) + u_b * sin(th); }`;

const LINE_VS = `
attribute float a_t;
uniform float u_span;
uniform vec2 u_shift;
varying float v_t, v_near;
${PROJECT}
${RING}
void main() {
  float th = (a_t - 0.5) * u_span;
  v_t = a_t;
  v_near = mix(1.0, 0.5 + 0.5 * cos(th), u_halo);
  gl_Position = place(onRing(th), u_ringNudge, 1.0);
  gl_Position.xy += u_shift * gl_Position.w;
}`;

const LINE_FS = `
precision mediump float;
${LIT}
uniform float u_draw, u_strength;
varying float v_t, v_near;
void main() {
  if (v_t > u_draw) discard;
  float a = u_strength * (0.27 + 0.38 * v_near) * smoothstep(0.0, 0.04, u_draw - v_t + 0.04);
  gl_FragColor = lit(vec3(0.941, 0.788, 0.529) * a);
}`;

const LIGHT_VS = `
attribute vec4 a_light; // angle round the ring, core radius in px, newest?, alpha
uniform float u_dpr, u_lightScale;
varying float v_core, v_size, v_newest, v_alpha;
${PROJECT}
${RING}
void main() {
  vec3 p = onRing(a_light.x);
  gl_Position = place(p, u_ringNudge, 1.0);
  float nearness = mix(1.0, clamp(1.0 / max(p.z, 0.1), 0.5, 1.4), u_halo);
  v_core = a_light.y * u_dpr * min(u_scale, 1.6) * nearness * u_lightScale;
  v_newest = a_light.z;
  v_alpha = a_light.w * mix(1.0, 0.45 + 0.55 * (0.5 + 0.5 * cos(a_light.x)), u_halo);
  v_size = v_core * (a_light.z > 0.5 ? 20.0 : 14.0);
  gl_PointSize = v_size;
}`;

const LIGHT_FS = `
precision mediump float;
${LIT}
varying float v_core, v_size, v_newest, v_alpha;
void main() {
  vec2 d = (gl_PointCoord - 0.5) * v_size / v_core;
  float r = length(d);
  vec3 col = smoothstep(1.15, 0.85, r) * vec3(1.0, 0.97, 0.9);
  col += exp(-r * r / 3.2) * vec3(1.0, 0.8, 0.5) * 0.8;
  col += exp(-r / 2.4) * vec3(1.0, 0.66, 0.36) * 0.3;
  if (v_newest > 0.5) {
    float w = 1.0 / max(v_core, 1.0);
    float cross = exp(-abs(d.x) / 3.4) * exp(-d.y * d.y / (w * w)) + exp(-abs(d.y) / 3.4) * exp(-d.x * d.x / (w * w));
    col += cross * vec3(1.0, 0.84, 0.59) * 0.7;
  }
  float edge = smoothstep(1.0, 0.7, r * 2.0 * v_core / v_size);
  gl_FragColor = lit(col * v_alpha * edge);
}`;

const clamp = (x: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
const easeOut = (x: number) => 1 - (1 - clamp(x)) ** 4;
const mix = (a: number, b: number, t: number) => a + (b - a) * t;
const step = (from: number, to: number, x: number) => {
  const t = clamp((x - from) / (to - from));
  return t * t * (3 - 2 * t);
};

function program(gl: WebGLRenderingContext, vs: string, fs: string) {
  const p = gl.createProgram()!;
  for (const [type, src] of [
    [gl.VERTEX_SHADER, vs],
    [gl.FRAGMENT_SHADER, fs],
  ] as const) {
    const s = gl.createShader(type)!;
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s) ?? "shader");
    gl.attachShader(p, s);
  }
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p) ?? "link");
  return { p, u: (name: string) => gl.getUniformLocation(p, name), a: (name: string) => gl.getAttribLocation(p, name) };
}
type Program = ReturnType<typeof program>;

function camera(name: ViewName) {
  const V = data.views[name];
  const ra = V.ra * 15 * DEG;
  const dec = V.dec * DEG;
  const fwd = [Math.cos(dec) * Math.cos(ra), Math.cos(dec) * Math.sin(ra), Math.sin(dec)];
  const n = Math.hypot(fwd[1], fwd[0]);
  let right = [fwd[1] / n, -fwd[0] / n, 0];
  let up = [right[1] * fwd[2] - right[2] * fwd[1], right[2] * fwd[0] - right[0] * fwd[2], right[0] * fwd[1] - right[1] * fwd[0]];
  const cr = Math.cos(V.roll * DEG);
  const sr = Math.sin(V.roll * DEG);
  [right, up] = [right.map((x, i) => x * cr + up[i] * sr), up.map((x, i) => x * cr - right[i] * sr)];
  return { V, fwd, right, up, focal: V.w / 2 / Math.tan((V.fov * DEG) / 2) };
}

export function Sky({ scene }: { scene: Scene }) {
  const root = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const glow = useRef<HTMLImageElement>(null);

  useEffect(() => {
    const el = root.current!;
    const cv = canvas.current!;
    const img = glow.current!;
    const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const tall = matchMedia(TALL);

    // If the sky cannot be drawn live, show the finished still instead.
    const fallBack = () => {
      const name = tall.matches ? SCENES[scene].tall : SCENES[scene].wide;
      img.parentElement?.querySelectorAll("source").forEach((source) => source.remove());
      img.src = `/sky/${name}.jpg`;
      img.style.transform = "none";
      img.style.opacity = "1";
    };
    const gl = cv.getContext("webgl", { alpha: true, premultipliedAlpha: true, antialias: false });
    if (!gl) return fallBack();
    let stars: Program, line: Program, light: Program;
    try {
      stars = program(gl, STAR_VS, STAR_FS);
      line = program(gl, LINE_VS, LINE_FS);
      light = program(gl, LIGHT_VS, LIGHT_FS);
    } catch {
      return fallBack();
    }

    const starBuf = gl.createBuffer();
    let starCount = 0;
    const SEGMENTS = 360;
    const lineBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, lineBuf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(Array.from({ length: SEGMENTS + 1 }, (_, i) => i / SEGMENTS)), gl.STATIC_DRAW);
    const lightBuf = gl.createBuffer();
    const lightData = new Float32Array(LIGHTS.length * 4);

    // The held scene at the top of the page, and the parts of it this script moves.
    const journey = scene === "hero" && !still ? el.closest<HTMLElement>(".journey") : null;
    const part = (name: string) => journey?.querySelector<HTMLElement>(name) ?? null;
    const words = part(".hero-words");
    const captionOne = part(".stage-one");
    const captionTwo = part(".stage-two");
    if (journey) journey.dataset.live = "";
    const show = (node: HTMLElement | null, opacity: number, transform: string) => {
      if (!node) return;
      node.style.opacity = opacity.toFixed(3);
      node.style.transform = transform;
      node.style.visibility = opacity < 0.004 ? "hidden" : "visible";
    };

    let W = 0;
    let H = 0;
    let dpr = 1;
    let raf = 0;
    let visible = true;
    let dead = false;
    let spin = 0; // the halo's own slow turning, in radians
    let last = 0;
    const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
    const born = performance.now();

    const resize = () => {
      const r = el.getBoundingClientRect();
      dpr = Math.min(devicePixelRatio || 1, 2);
      W = r.width;
      H = r.height;
      cv.width = Math.round(W * dpr);
      cv.height = Math.round(H * dpr);
    };

    const draw = (now: number) => {
      raf = 0;
      if (dead || !visible || !W) return;
      const t = (now - born) / 1000;
      const dt = Math.min(0.05, last ? (now - last) / 1000 : 0);
      last = now;
      const rect = el.getBoundingClientRect();
      const vh = innerHeight;
      const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
      const cam = camera(tall.matches ? SCENES[scene].tall : SCENES[scene].wide);
      const cover = Math.max(W / cam.V.w, H / cam.V.h);
      const focal = cam.focal * cover;
      pointer.x += (pointer.tx - pointer.x) * 0.06;
      pointer.y += (pointer.ty - pointer.y) * 0.06;

      // How things stand right now.
      let scale = 1; // how near the sky is
      let roll = 0; // how far it has turned
      let fade = 1;
      let drawn = 1; // how much of the ring's line is drawn
      let rush = 0; // extra nearness for the near stars
      let travel = 0; // how far up the nearest stars have moved, in px
      let halo = scene === "close" ? 1 : 0; // 0: the arc overhead. 1: the whole halo.
      let turned = 0; // how far the halo has been turned by the scroll
      let lean = 20 * DEG; // how far the halo is tipped toward us
      let rise = scene === "close" ? 0.27 : 0.19; // how far above the middle the halo sits
      const lit = LIGHTS.map(() => 1);

      if (!still) {
        if (scene === "hero") {
          const e = easeOut(t / 3.2);
          const jr = (journey ?? el).getBoundingClientRect();
          const p = journey ? clamp(-jr.top / Math.max(1, jr.height - vh)) : 0;
          scale = (0.85 + 0.15 * e) * (1 + 0.16 * p);
          roll = (-3 * (1 - e) + 5 * p) * DEG;
          fade = clamp(t / 1.4);
          drawn = easeOut((t - 0.2) / 3);
          rush = -0.45 * (1 - e) + 0.3 * p;
          travel = -(0.62 * p + clamp(1 - jr.bottom / vh) * 0.2) * H;
          halo = step(0.05, 0.5, p);
          turned = 2.4 * step(0.22, 1, p) * Math.PI;
          lean = mix(16, 30, step(0.4, 1, p)) * DEG;
          LIGHTS.forEach((l, i) => {
            lit[i] = l.round === undefined ? easeOut((t - 0.9 - i * 0.55) / 2.6) : step(0.25, 0.5, p);
          });
          if (journey) {
            show(words, 1 - step(0.01, 0.11, p), `translate3d(0, ${(-80 * step(0, 0.13, p)).toFixed(1)}px, 0)`);
            show(captionOne, step(0.2, 0.3, p) * (1 - step(0.52, 0.6, p)), `translate3d(0, ${(24 * (1 - step(0.2, 0.3, p)) - 24 * step(0.52, 0.6, p)).toFixed(1)}px, 0)`);
            show(captionTwo, step(0.64, 0.74, p), `translate3d(0, ${(24 * (1 - step(0.64, 0.74, p))).toFixed(1)}px, 0)`);
          }
        } else {
          const p = clamp((vh - rect.top) / (vh + H));
          scale = 0.94 + 0.16 * p;
          roll = (p - 0.5) * 6 * DEG;
          drawn = clamp((p - 0.1) / 0.35);
          rush = (p - 0.6) * 0.3;
          travel = (0.5 - p) * 0.5 * H;
          turned = p * 1.5 * Math.PI;
          lean = mix(12, 24, p) * DEG;
          LIGHTS.forEach((_, i) => (lit[i] = clamp((p - 0.18 - i * 0.025) / 0.15)));
        }
        spin += dt * 0.07 * halo;
      }

      const nudgeX = pointer.x * 22;
      const nudgeY = pointer.y * 16;
      img.style.transform = `translate3d(${(nudgeX * 0.12).toFixed(2)}px, ${(travel * 0.07 + nudgeY * 0.12).toFixed(2)}px, 0) rotate(${roll.toFixed(5)}rad) scale(${(data.oversize * scale).toFixed(5)})`;
      img.style.opacity = cv.style.opacity = fade.toFixed(3);

      gl.viewport(0, 0, cv.width, cv.height);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

      const common = (pr: Program) => {
        gl.useProgram(pr.p);
        gl.uniform1f(pr.u("u_focal"), focal);
        gl.uniform1f(pr.u("u_scale"), scale);
        gl.uniform2f(pr.u("u_rot"), Math.cos(roll), Math.sin(roll));
        gl.uniform2f(pr.u("u_half"), W / 2, H / 2);
        gl.uniform1f(pr.u("u_dpr"), dpr);
      };

      if (starCount) {
        common(stars);
        gl.uniform3fv(stars.u("u_right"), cam.right);
        gl.uniform3fv(stars.u("u_up"), cam.up);
        gl.uniform3fv(stars.u("u_fwd"), cam.fwd);
        gl.uniform2f(stars.u("u_travel"), nudgeX, travel + nudgeY);
        gl.uniform1f(stars.u("u_sig"), (cam.V.w / data.ref) * cover * Math.min(scale, 1.5));
        gl.uniform1f(stars.u("u_rush"), rush);
        gl.bindBuffer(gl.ARRAY_BUFFER, starBuf);
        gl.enableVertexAttribArray(stars.a("a_dir"));
        gl.vertexAttribPointer(stars.a("a_dir"), 3, gl.FLOAT, false, 20, 0);
        gl.enableVertexAttribArray(stars.a("a_mb"));
        gl.vertexAttribPointer(stars.a("a_mb"), 2, gl.FLOAT, false, 20, 12);
        gl.drawArrays(gl.POINTS, 0, starCount);
      }

      // The ring, in the camera's own frame: x right, y up, z ahead.
      // As the arc overhead, it is a circle on the sky whose lowest point sits a little above the
      // middle of the view, at the height the page gives it.
      const arcY = Math.min(0.2 * vh + 0.12 * Math.max(W, 16 * rem * 2.6), H * 0.46);
      const phi = ARC_RADIUS + Math.atan((H / 2 - arcY) / focal);
      const ct = Math.cos(ARC_TILT);
      const st = Math.sin(ARC_TILT);
      const tilt = (v: number[]) => [v[0] * ct - v[1] * st, v[0] * st + v[1] * ct, v[2]];
      const cosR = Math.cos(ARC_RADIUS);
      const sinR = Math.sin(ARC_RADIUS);
      const arc = {
        c: tilt([0, Math.sin(phi) * cosR, Math.cos(phi) * cosR]),
        a: tilt([0, -Math.cos(phi) * sinR, Math.sin(phi) * sinR]),
        b: tilt([sinR, 0, 0]),
      };
      // As a halo, it is a ring out in front of us, tipped so its near edge hangs lowest.
      const radius = Math.min(0.34, (0.3 * W) / focal) * (scene === "close" ? 0.72 : 1);
      const whole = {
        c: [0, (rise * H) / focal, 1],
        a: [0, -Math.sin(lean) * radius, -Math.cos(lean) * radius],
        b: [radius, 0, 0],
      };
      const between = (k: "c" | "a" | "b") => arc[k].map((v, i) => mix(v, whole[k][i], halo));
      // The stretch of the arc that crosses the view, as an angle round the ring.
      const across = (2 * Math.atan(W / 2 / focal)) / sinR;
      const round = turned + spin;
      const ring = (pr: Program) => {
        gl.uniform3fv(pr.u("u_c"), between("c"));
        gl.uniform3fv(pr.u("u_a"), between("a"));
        gl.uniform3fv(pr.u("u_b"), between("b"));
        gl.uniform1f(pr.u("u_halo"), halo);
        gl.uniform2f(pr.u("u_ringNudge"), nudgeX * 1.6, nudgeY * 1.6);
      };

      common(line);
      ring(line);
      gl.uniform1f(line.u("u_span"), mix(across * 2.4, 2 * Math.PI, halo * halo));
      gl.uniform1f(line.u("u_draw"), drawn);
      gl.bindBuffer(gl.ARRAY_BUFFER, lineBuf);
      gl.enableVertexAttribArray(line.a("a_t"));
      gl.vertexAttribPointer(line.a("a_t"), 1, gl.FLOAT, false, 0, 0);
      // A GL line is one device pixel wide whatever is asked, which Noah found too faint. So it is
      // drawn twice, the second a pixel across and down and a little weaker: nearly two pixels.
      gl.uniform2f(line.u("u_shift"), 0, 0);
      gl.uniform1f(line.u("u_strength"), 1);
      gl.drawArrays(gl.LINE_STRIP, 0, SEGMENTS + 1);
      gl.uniform2f(line.u("u_shift"), 2 / gl.drawingBufferWidth, -2 / gl.drawingBufferHeight);
      gl.uniform1f(line.u("u_strength"), 0.7);
      gl.drawArrays(gl.LINE_STRIP, 0, SEGMENTS + 1);

      LIGHTS.forEach((l, i) => {
        const angle = l.round ?? ((l.at ?? 0.5) - 0.5) * across * 1.04;
        lightData.set([angle + round, l.size * rem * 0.25, l.newest ? 1 : 0, lit[i]], i * 4);
      });
      common(light);
      ring(light);
      // A small halo carries smaller lights, so they stay distinct.
      gl.uniform1f(light.u("u_lightScale"), mix(1, clamp(radius / 0.34, 0.5, 1), halo));
      gl.bindBuffer(gl.ARRAY_BUFFER, lightBuf);
      gl.bufferData(gl.ARRAY_BUFFER, lightData, gl.DYNAMIC_DRAW);
      gl.enableVertexAttribArray(light.a("a_light"));
      gl.vertexAttribPointer(light.a("a_light"), 4, gl.FLOAT, false, 0, 0);
      gl.drawArrays(gl.POINTS, 0, LIGHTS.length);

      el.dataset.live = "";
      // Keep going while there is something still moving: the opening, the halo, or the pointer.
      const settling = Math.abs(pointer.tx - pointer.x) + Math.abs(pointer.ty - pointer.y) > 0.002;
      if (!still && ((scene === "hero" && t < 6.5) || halo > 0 || settling)) request();
    };

    const request = () => {
      if (!raf && !dead) raf = requestAnimationFrame(draw);
    };
    const onScroll = () => {
      if (visible && !still) request();
    };
    const onPointer = (event: PointerEvent) => {
      if (still || event.pointerType !== "mouse") return;
      pointer.tx = (event.clientX / innerWidth) * 2 - 1;
      pointer.ty = (event.clientY / innerHeight) * 2 - 1;
      if (visible) request();
    };

    fetch(`/sky/${scene}.stars`)
      .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject()))
      .then((buf) => {
        if (dead) return;
        const view = new DataView(buf);
        const n = Math.floor(buf.byteLength / 6);
        const arr = new Float32Array(n * 5);
        for (let i = 0; i < n; i++) {
          const ra = (view.getUint16(i * 6, true) / 65536) * 2 * Math.PI;
          const dec = (view.getInt16(i * 6 + 2, true) / 32767) * (Math.PI / 2);
          arr.set([Math.cos(dec) * Math.cos(ra), Math.cos(dec) * Math.sin(ra), Math.sin(dec), view.getUint8(i * 6 + 4) / 20 - 2, view.getUint8(i * 6 + 5) / 100 - 0.5], i * 5);
        }
        gl.bindBuffer(gl.ARRAY_BUFFER, starBuf);
        gl.bufferData(gl.ARRAY_BUFFER, arr, gl.STATIC_DRAW);
        starCount = n;
        request();
      })
      .catch(() => {});

    const ro = new ResizeObserver(() => {
      resize();
      request();
    });
    ro.observe(el);
    const io = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      last = 0;
      if (visible) request();
    });
    io.observe(el);
    addEventListener("scroll", onScroll, { passive: true });
    addEventListener("pointermove", onPointer, { passive: true });
    tall.addEventListener("change", request);
    resize();
    request();

    return () => {
      dead = true;
      cancelAnimationFrame(raf);
      if (journey) delete journey.dataset.live;
      ro.disconnect();
      io.disconnect();
      removeEventListener("scroll", onScroll);
      removeEventListener("pointermove", onPointer);
      tall.removeEventListener("change", request);
    };
  }, [scene]);

  const { wide, tall } = SCENES[scene];
  const V = data.views[wide];
  return (
    <div className="sky" ref={root} aria-hidden="true">
      <picture>
        {tall !== wide && (
          <>
            <source media={TALL} type="image/avif" srcSet={`/sky/${tall}-glow.avif`} />
            <source media={TALL} type="image/webp" srcSet={`/sky/${tall}-glow.webp`} />
            <source media={TALL} srcSet={`/sky/${tall}-glow.jpg`} />
          </>
        )}
        <source type="image/avif" srcSet={`/sky/${wide}-glow.avif`} />
        <source type="image/webp" srcSet={`/sky/${wide}-glow.webp`} />
        <img
          ref={glow}
          src={`/sky/${wide}-glow.jpg`}
          alt=""
          width={V.w}
          height={V.h}
          style={{ transform: `scale(${data.oversize})` }}
          fetchPriority={scene === "hero" ? "high" : undefined}
          loading={scene === "hero" ? undefined : "lazy"}
          decoding="async"
        />
      </picture>
      <canvas ref={canvas} />
    </div>
  );
}
