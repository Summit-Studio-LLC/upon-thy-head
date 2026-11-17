#version 460 core
#include <flutter/runtime_effect.glsl>

// The night behind everything: the Milky Way wrapped on the celestial sphere,
// seen through a stereographic camera, plus the breathing glow used while recording.
// Ported from the WebGL prototype (design/prototype/src/app.js, pBg).

precision highp float;

// The numbers arrive packed four to a vec4: Impeller on Metal gives every uniform its own buffer,
// and the iOS 17 simulator allows only 14 (18 loose ones crashed it, Q61). The names below are
// the ones the code uses; lib/sky/sky_painter.dart writes the floats in this order.
uniform vec4 uP0;     // uSize, uDpr, uCy
uniform vec4 uP1;     // uF, uExp
uniform vec4 uP2;     // uR, uHas
uniform vec4 uP3;     // uU, uSoft
uniform vec4 uP4;     // uT, uTex
uniform vec4 uP5;     // uTexS, unused
uniform vec4 uOrb;    // glow: centre x, centre y (clip units), radius, strength
uniform vec3 uSky;    // base sky colour (linear)
uniform vec3 uTint;   // palette tint of the Milky Way
uniform vec3 uO1;
uniform vec3 uO2;
uniform vec3 uO3;
#define uSize uP0.xy  // logical size of the canvas
#define uDpr  uP0.z   // device pixels per logical pixel
#define uCy   uP0.w   // vertical offset of the look point, in clip units
#define uF    uP1.xyz // camera forward
#define uExp  uP1.w   // exposure of the Milky Way
#define uR    uP2.xyz // camera right
#define uHas  uP2.w   // 1 when the texture is loaded
#define uU    uP3.xyz // camera up
#define uSoft uP3.w   // 0 at the home framing, rising to 1 as the view zooms in
#define uT    uP4.xy  // tangent scale (x, y)
#define uTex  uP4.zw  // texture size in texels
#define uTexS uP5.xy  // size of the soft copy in texels
uniform sampler2D uMW;
uniform sampler2D uMWs; // the Milky Way at half size, averaged in linear light

out vec4 fragColor;

float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * .1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

// Bilinear by hand from four nearest-neighbour fetches. Impeller's own linear
// sampling of this texture came out markedly brighter than the prototype
// (measured on the iOS simulator), so the sampler is left at nearest.
vec3 mw(vec2 uv) {
  vec2 p = uv * uTex - .5;
  vec2 f = fract(p);
  vec2 b = (floor(p) + .5) / uTex;
  vec2 o = 1. / uTex;
  vec3 a = mix(texture(uMW, b).rgb, texture(uMW, b + vec2(o.x, 0.)).rgb, f.x);
  vec3 c = mix(texture(uMW, b + vec2(0., o.y)).rgb, texture(uMW, b + o).rgb, f.x);
  return mix(a, c, f.y);
}

// Cubic B-spline from sixteen nearest fetches: smooth to the second
// derivative, so a low-resolution texture magnified many times shows no
// creases. Used for the soft copy only, and only when zoomed in.
vec3 mwSoft(vec2 uv) {
  vec2 p = uv * uTexS - .5;
  vec2 f = fract(p);
  vec2 b = floor(p);
  vec2 f2 = f * f, f3 = f2 * f;
  vec4 wx = vec4(1. - 3. * f.x + 3. * f2.x - f3.x, 4. - 6. * f2.x + 3. * f3.x, 1. + 3. * f.x + 3. * f2.x - 3. * f3.x, f3.x) / 6.;
  vec4 wy = vec4(1. - 3. * f.y + 3. * f2.y - f3.y, 4. - 6. * f2.y + 3. * f3.y, 1. + 3. * f.y + 3. * f2.y - 3. * f3.y, f3.y) / 6.;
  vec3 c = vec3(0.);
  for (int j = 0; j < 4; j++) {
    vec3 row = vec3(0.);
    for (int i = 0; i < 4; i++) {
      vec2 t = (b + vec2(float(i) - 1., float(j) - 1.) + .5) / uTexS;
      t.x = fract(t.x);                 // right ascension wraps
      t.y = clamp(t.y, .5 / uTexS.y, 1. - .5 / uTexS.y);
      row += texture(uMWs, t).rgb * wx[i];
    }
    c += row * wy[j];
  }
  return c;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 vN = vec2(px.x / uSize.x * 2. - 1., 1. - px.y / uSize.y * 2.);
  float asp = uSize.x / uSize.y;

  vec2 q = vec2(vN.x * uT.x, (vN.y - uCy) * uT.y);
  float r2 = dot(q, q);
  vec3 d = normalize(uF * (4. - r2) + (uR * q.x + uU * q.y) * 4.);
  vec2 uv = vec2(.5 - atan(d.y, d.x) / 6.28318531, .5 - asin(clamp(d.z, -1., 1.)) / 3.14159265);

  vec3 t = pow(mw(uv) * uHas, vec3(1.3333 * 2.2)); // undo the storage lift, then to linear light
  // Zoomed in, the full texture's grain would be magnified into smudges; the
  // soft copy keeps the Milky Way's structure without it.
  if (uSoft > 0.) {
    vec3 s = pow(max(mwSoft(uv), 0.) * uHas, vec3(1.3333 * 2.2));
    t = mix(t, s, uSoft);
  }
  vec3 lin = t * uTint * uExp * 3.4 + uSky * (.35 + .65 * uExp);
  vec3 c = 1. - exp(-lin * 1.9);
  c = pow(c, vec3(.4545));

  vec2 e = vN * vec2(asp, 1.);
  c *= 1. - .22 * smoothstep(.55, 1.25, length(e));

  float od = length((vN - uOrb.xy) * vec2(asp, 1.)) / uOrb.z;
  vec3 orb = uO1 * exp(-od * od * 3.2) * .5 + uO2 * exp(-od * 1.6) * .4
      + uO3 * .15 / (1. + od * od * 1.1) * smoothstep(5.5, 1., od);
  c += orb * uOrb.w;

  c += (hash(floor(px * uDpr)) - .5) / 255. * 1.6;
  fragColor = vec4(clamp(c, 0., 1.), 1.);
}
