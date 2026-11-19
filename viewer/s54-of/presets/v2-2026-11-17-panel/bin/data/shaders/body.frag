#version 150
// S54 garden: one life's body on the 24x24 torus from the recomputed reference (BodyView.cpp).
// texel (x, y) of uTex = site i with i - 1 = y*24 + x: r = C (constituent present), g = B (binding matter), b = A (ambient matter).
// uMode 1: the grid as it is (nearest cell). uMode 2: a smooth field (cubic B-spline over cell centres, wrapping).
uniform sampler2D uTex;
uniform int uMode;
uniform vec2 uOff;      // cell coordinate at the centre of the view
uniform float uSpan;    // cells across the quad
uniform float uPx;      // quad width in pixels
uniform float uWC, uWB, uWA, uIso, uSoft, uGlow, uShimmer, uGridLines, uGap;
uniform float uHue, uSat, uVal, uHaze, uAlive, uTime, uMis, uStale;
in vec2 vUv;
out vec4 outputColor;

vec4 cell(ivec2 c) { c = ((c % 24) + 24) % 24; return texelFetch(uTex, c, 0); }
vec3 hsv(float h, float s, float v) {
    vec3 k = clamp(abs(mod(h * 6.0 + vec3(0, 4, 2), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return v * mix(vec3(1.0), k, s);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; ++i) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}
vec4 wts(float f) {
    float f2 = f * f, f3 = f2 * f;
    return vec4((1.0 - f) * (1.0 - f) * (1.0 - f), 3.0 * f3 - 6.0 * f2 + 4.0, -3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0, f3) / 6.0;
}
vec4 bspline(vec2 p) {
    vec2 q = p - 0.5;
    vec2 i = floor(q), f = q - i;
    vec4 wx = wts(f.x), wy = wts(f.y);
    ivec2 b = ivec2(i);
    vec4 s = vec4(0.0);
    for (int j = 0; j < 4; ++j)
        for (int k = 0; k < 4; ++k) s += wx[k] * wy[j] * cell(b + ivec2(k - 1, j - 1));
    return s;
}

void main() {
    vec2 p = uOff + (vUv - 0.5) * uSpan;
    float aa = uSpan / uPx; // cells per pixel
    vec3 bg = vec3(0.012, 0.016, 0.035);
    vec3 col = hsv(uHue, uSat * (0.35 + 0.65 * uAlive), uVal);
    vec3 haze = hsv(fract(uHue + uHaze), 0.5, 0.55);
    vec3 c = bg;
    float t = uTime;
    vec2 e2 = min(fract(p), 1.0 - fract(p));
    float lines = 1.0 - smoothstep(0.0, aa * 1.5, min(e2.x, e2.y));
    if (uMode == 1) {
        vec2 ci = floor(p), f = p - ci;
        vec4 v = cell(ivec2(ci));
        float g = uGap * 0.5;
        vec2 e = min(f, 1.0 - f);
        float inside = smoothstep(g - aa, g + aa, min(e.x, e.y));
        float b = clamp(v.g * uWB, 0.0, 1.0), a = clamp(v.b * uWA, 0.0, 1.0), on = v.r * uWC;
        c += haze * a * 0.30 * inside;
        c += col * inside * on * (0.35 + 0.65 * b) * (0.25 + 0.75 * uAlive);
        c += col * 0.22 * b * inside * (1.0 - v.r);
        float dr = 0.06 + 0.22 * a;
        c += haze * 0.6 * a * (1.0 - v.r) * smoothstep(dr + aa, dr - aa, length(f - 0.5));
        c += vec3(0.6, 0.65, 0.8) * uGridLines * 0.22 * lines;
    } else {
        vec2 w = vec2(fbm(p * 0.55 + t * 0.07), fbm(p * 0.55 - t * 0.06 + 3.1)) - 0.5;
        vec4 v = bspline(p + w * uShimmer * 0.9);
        float d = uWC * v.r + uWB * v.g;
        float body = smoothstep(uIso - uSoft, uIso + uSoft, d);
        float rim = exp(-pow((d - uIso) / max(uSoft, 0.02), 2.0));
        float diss = smoothstep(0.0, 1.0, (1.0 - uAlive) * 1.2 - fbm(p * 1.3 + t * 0.05) + 0.2);
        float grain = 0.78 + 0.22 * fbm(p * 2.2 + vec2(t * 0.11, -t * 0.08));
        c += haze * clamp(v.b * uWA, 0.0, 1.0) * 0.40;
        c += col * body * (0.28 + 0.6 * clamp(v.g, 0.0, 1.0)) * grain * (1.0 - diss);
        c += mix(col, vec3(1.0), 0.35) * rim * 0.5 * (1.0 - diss);
        c += col * uGlow * 0.30 * smoothstep(0.0, max(uIso, 0.05), d) * (1.0 - body * 0.6);
        c += vec3(0.6, 0.65, 0.8) * uGridLines * 0.10 * lines;
        float m = smoothstep(0.5, 0.36, length(vUv - 0.5)); // round window onto the torus
        c = bg + (c - bg) * m;
    }
    float g = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(c, vec3(1.0, 0.12, 0.1) * (0.3 + g), 0.55 * uMis);
    c = mix(c, vec3(g) * 0.6, uStale * 0.85);
    outputColor = vec4(pow(max(c, 0.0), vec3(0.9)), 1.0);
}
