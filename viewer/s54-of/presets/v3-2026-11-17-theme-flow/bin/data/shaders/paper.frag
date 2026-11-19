#version 150
// S54 garden: the light theme. The picture is drawn as light on a dark ground (every look); here it is turned into
// ink on paper: the paper where there was no light, a pigment of the light's hue where there was (white light -> ink).
// The hue is kept, so the colours still come from the same values; only the ground and the sense of brightness flip.
uniform sampler2DRect uTex;
uniform vec2 uRes;      // window pixels
uniform vec2 uTexSize;  // picture pixels (renderScale)
uniform vec3 uPaper, uInk;
out vec4 outputColor;
void main() {
    vec2 uv = gl_FragCoord.xy / uRes;
    uv.y = 1.0 - uv.y; // the fbo holds the picture top row first
    vec3 c = texture(uTex, uv * uTexSize).rgb;
    float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
    float sat = mx > 1e-4 ? (mx - mn) / mx : 0.0;
    vec3 chroma = mx > 1e-4 ? c / mx : vec3(0.0);
    vec3 pigment = mix(uInk, chroma * 0.66, smoothstep(0.0, 0.6, sat));
    // the dark ground of the looks (up to about 0.07 with its texture) stays paper
    float a = clamp(1.0 - exp(-2.6 * max(mx - 0.07, 0.0)), 0.0, 1.0);
    outputColor = vec4(mix(uPaper, pigment, a), 1.0);
}
