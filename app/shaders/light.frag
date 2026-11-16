#version 460 core
#include <flutter/runtime_effect.glsl>

// One blessing: a warm point of light with a soft glow and a faint cross.
// Drawn additively over the sky. Ported from the WebGL prototype (pLi).

precision highp float;

uniform vec2 uC;     // centre, logical pixels
uniform float uRad;  // half-size of the quad, logical pixels
uniform float uFoc;  // 0 resting, 1 in focus
uniform float uA;    // overall strength
uniform vec3 uL1;
uniform vec3 uL2;
uniform vec3 uL3;

out vec4 fragColor;

void main() {
  vec2 vP = (FlutterFragCoord().xy - uC) / uRad;
  float d = length(vP);
  float r = d * uRad;
  float f = uFoc;
  float s = mix(1.5, 2.5, f);
  float core = exp(-r * r / (2. * s * s)) * 1.3;
  float glow = exp(-r / mix(4.5, 9., f)) * mix(.5, .8, f);
  float halo = mix(.05, .15, f) / (1. + r * r / mix(120., 520., f));
  vec2 a = abs(vP) * uRad;
  float L = mix(7., 24., f);
  float sp = (exp(-a.y * a.y / .42) * exp(-a.x / L) + exp(-a.x * a.x / .42) * exp(-a.y / L)) * mix(.1, .42, f);
  vec3 col = uL1 * core + uL2 * (glow + sp) + uL3 * halo;
  col = clamp(col * smoothstep(1., .45, d) * uA, 0., 1.);
  fragColor = vec4(col, max(col.r, max(col.g, col.b)));
}
