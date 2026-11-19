#version 150
// S54 garden: two lives (left trial-1 L2, right trial-2 L2+SF) as glowing bodies.
// size breathes with each note (the reference hash of the step), swirl follows the world's yield,
// a ring shows progress toward the reference death, red glitch = reference mismatch, grey = stale data.
uniform float uTime;
uniform vec2 uRes;
uniform float uAlive[2];
uniform float uProg[2];
uniform float uHue[2];
uniform float uYield[2];
uniform float uPulse[2];
uniform float uMis[2];
uniform float uStale;
uniform float uHeat;
uniform float uFsBad;
uniform float uFlash;
out vec4 outputColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; ++i) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}
vec3 hsv(float h, float s, float v) {
    vec3 k = clamp(abs(mod(h * 6.0 + vec3(0, 4, 2), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return v * mix(vec3(1.0), k, s);
}

vec3 body(vec2 uv, int i, vec2 c) {
    float al = uAlive[i];
    vec2 q = uv - c;
    float t = uTime * (0.15 + 0.35 * uYield[i]);
    // domain warp
    vec2 w = vec2(fbm(q * 3.0 + t), fbm(q * 3.0 - t + 4.0)) - 0.5;
    if (uMis[i] > 0.5) q.x += 0.04 * step(0.5, fract(uv.y * 40.0 + uTime * 3.0)) * sin(uTime * 20.0);
    float field = 0.0;
    for (int k = 0; k < 5; ++k) {
        float a = float(k) * 1.2566 + uTime * 0.2 * (1.0 + float(k) * 0.3) + uHue[i] * 6.283;
        vec2 o = vec2(cos(a), sin(a)) * (0.05 + 0.03 * float(k)) * (0.6 + 0.4 * al);
        float r = (0.05 + 0.025 * uPulse[i]) * (0.25 + 0.75 * al);
        field += r * r / (dot(q + w * 0.12 - o, q + w * 0.12 - o) + 1e-4);
    }
    // dying bodies dissolve into the noise
    float diss = smoothstep(0.0, 1.0, (1.0 - al) * 1.2 - fbm(q * 9.0 + uTime * 0.1) + 0.2);
    float m = smoothstep(0.8, 1.6, field) * (1.0 - diss);
    float rim = smoothstep(0.5, 0.9, field) - smoothstep(0.9, 1.4, field);
    vec3 col = hsv(uHue[i], 0.75 * (0.3 + 0.7 * al), 1.0);
    if (uMis[i] > 0.5) col = mix(col, vec3(1.0, 0.1, 0.1), 0.8);
    vec3 outc = col * m * (0.45 + 0.5 * uPulse[i]) + col * rim * 0.6 * (1.0 - diss);
    outc += col * 0.004 / (dot(q, q) + 0.03) * (0.2 + 0.8 * al);
    // progress ring toward the reference death
    float d = length(q), ang = atan(q.y, q.x) / 6.2831853 + 0.5;
    float ring = smoothstep(0.004, 0.0, abs(d - 0.30)) * step(ang, uProg[i]);
    float track = smoothstep(0.003, 0.0, abs(d - 0.30)) * 0.12;
    outc += vec3(0.9) * ring * 0.8 + vec3(0.6) * track;
    return outc;
}

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
    if (uHeat > 0.5) uv += 0.004 * vec2(sin(uv.y * 60.0 + uTime * 8.0), 0.0);
    float aspect = uRes.x / uRes.y;
    vec2 c0 = vec2(-0.27 * aspect, 0.05), c1 = vec2(0.27 * aspect, 0.05);
    vec3 col = vec3(0.01, 0.015, 0.04) + 0.05 * vec3(0.2, 0.3, 0.6) * fbm(uv * 2.0 + uTime * 0.02);
    col += body(uv, 0, c0) + body(uv, 1, c1);
    // filesystem trouble: red cracks
    if (uFsBad > 0.5) {
        float n = abs(fbm(uv * 6.0) - 0.5);
        col += vec3(0.8, 0.05, 0.05) * smoothstep(0.02, 0.0, n);
    }
    // a reboot happened: a ring of light from the center
    float r = length(uv);
    col += vec3(1.0) * uFlash * smoothstep(0.03, 0.0, abs(r - (1.0 - uFlash) * 1.2));
    // stale data: grey and dark edges
    float g = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(g) * 0.6, uStale * 0.85);
    col *= 1.0 - (0.35 + 0.4 * uStale) * dot(uv, uv);
    outputColor = vec4(pow(max(col, 0.0), vec3(0.85)), 1.0);
}
