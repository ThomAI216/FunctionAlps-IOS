#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// The "slosh" progress fill — the Metal Forge preset the owner tuned (2026-09-06), ported from the WebGL
// mockup one-to-one. The fill is a signed distance to a wavy front; inside is a ramp through c1 → c2,
// brightening to c3 / c4 in the last stretch; the edge is c5 over c4 with a soft bloom; six trailing
// filaments echo behind it; a little haze crosses into the empty part. The empty part is TRANSPARENT so
// the bar's hashed track shows through (alpha = coverage + glow).
//
// Preset (from the owner's sliders): speed .45 · scale 15.5 · amount .03 · echo .064 · bloom .2 · jitter 0
// frontIn -.26 · frontOut .09 · churn 1 · feather .8 · stagger .46 · pulse .3 @ 5 · turbulence .3
// sparkle 1.4 · ripple 2 · falloff 1.5 · trails 6 · trailGlow 2 · haze 1.8 · grain 0.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
    return v;
}

// The effect itself, in a unit square: x = the progress axis, y = across the bar. Both the bar and the
// ring sample this (the ring maps angle → x, radius → y).
static half4 sloshSample(float2 uv, float time, float progress, float3 c1, float3 c2, float3 c3, float3 c4, float3 c5) {
    // Preset (the owner's sliders, 2026-09-06; echo tightened the same day): speed .45 · scale 15.5 ·
    // amount .03 · echo .034 · bloom .2 · frontIn -.26 · frontOut .09 · churn 1 · feather .8 · stagger .46 ·
    // pulse .3 @ 5 · turbulence .3 · sparkle 1.4 · ripple 2 · falloff 1.5 · trails 6 · trailGlow 2 · haze 1.8.
    const float speed = 0.45, scale = 15.5, amount = 0.03, echo = 0.034, bloom = 0.2;
    const float frontIn = -0.26, frontOut = 0.09, churn = 1.0, feather = 0.8, stagger = 0.46;
    const float pulseAmt = 0.3, pulseRate = 5.0, turb = 0.3, sparkle = 1.4, ripple = 2.0;
    const float falloff = 1.5, trails = 6.0, trailGlow = 2.0, haze = 1.8;

    float t = time * speed;
    float y = uv.y;

    // ── the front: one smooth slosh, a little turbulence on top ──
    float n1 = fbm(float2(y * 1.35 + 0.3 + stagger * 0.5, t * 0.32));
    float n2 = fbm(float2(y * scale * 0.32 - t * 0.55, 7.0 + t * 0.4 * churn)) * turb;
    float wave = (n1 - 0.5) * 2.4 + (n2 - 0.5) * 0.45;
    float rip = sin(y * 7.0 - t * 3.0) * 0.006 * ripple;
    // full = solid to the far edge; the wave never leaves a gap at 100 %
    float p = progress >= 0.999 ? 1.3 : progress;
    float frontX = p + wave * amount + rip;

    float dx = uv.x - frontX;                  // < 0 inside the fill
    float inside = 1.0 - smoothstep(frontIn * feather * 0.35, frontOut * feather * 0.35, dx);

    // ── body: the far (left) end is lit too — c2 is reached early, the currents only add light ──
    float along = clamp(uv.x / max(frontX, 0.001), 0.0, 1.0);
    float3 body = mix(c1, c2, smoothstep(0.0, 0.4, along));
    float cur = fbm(float2(uv.x * 2.5 - t * 0.3, uv.y * 3.0 + t * 0.2 * churn));
    body *= 0.95 + 0.35 * cur;
    body = mix(body, c3, smoothstep(-0.3, 0.0, dx) * 0.85);
    body = mix(body, c4, smoothstep(-0.09, 0.0, dx) * 0.55);

    // ── edge + bloom ──
    float pulse = 1.0 + pulseAmt * 0.5 * (0.5 + 0.5 * sin(time * pulseRate * 0.6));
    float edgeW = 0.007 + 0.016 * bloom;
    float edge = exp(-abs(dx) / edgeW);
    float glow = exp(-abs(dx) / (edgeW * 5.0)) * 0.45 * bloom;
    float fil = smoothstep(0.3, 0.9, fbm(float2(y * 3.5 + t * 0.8, 2.0 + t * 0.2)));
    float3 col = body * inside;
    col += c4 * (glow * inside + glow * (1.0 - inside) * 0.55) * pulse;
    col += mix(c4, c5, 0.35 + 0.65 * fil) * edge * (0.75 + 0.55 * fil) * pulse;
    col += c5 * pow(edge, 2.5) * sparkle * 0.35 * fil;

    // ── trails: close behind the front (echo), thinner, fading with falloff ──
    for (int k = 1; k <= 6; k++) {
        float kf = float(k);
        if (kf > trails) { break; }
        float ghostX = frontX - echo * kf * (0.75 + 0.5 * n1);
        float gd = abs(uv.x - ghostX);
        float g = exp(-gd / (0.005 + 0.003 * kf)) * pow(1.0 - kf / (trails + 1.0), falloff) * trailGlow;
        col += mix(c4, c3, kf / (trails + 1.0)) * g * 0.5 * inside * (0.6 + 0.4 * fil);
    }

    // ── haze past the edge (adds a little alpha into the empty part) ──
    float hz = exp(-max(dx, 0.0) / 0.18) * 0.14 * haze * (0.5 + 0.5 * n1);
    col += c3 * hz * (1.0 - inside);

    float alpha = clamp(inside + glow * (1.0 - inside) * 1.2 + hz * (1.0 - inside) * 2.0 + edge * (1.0 - inside) * 0.8, 0.0, 1.0);
    col = clamp(col, 0.0, 1.0);
    return half4(half3(col * alpha), half(alpha));   // premultiplied
}

/// The bar: x across the width, y across the height.
[[ stitchable ]] half4 slosh(float2 position, half4 color, float2 size, float time, float progress,
                             half4 c1h, half4 c2h, half4 c3h, half4 c4h, half4 c5h) {
    if (progress <= 0.002) { return half4(0.0); }
    float2 uv = position / max(size, float2(1.0));
    return sloshSample(uv, time, progress, float3(c1h.rgb), float3(c2h.rgb), float3(c3h.rgb), float3(c4h.rgb), float3(c5h.rgb));
}

/// The ring: angle from the top, clockwise → x; the band from the inner radius outward → y.
/// `thickness` is the stroke width in points; the band edges are anti-aliased over one point.
[[ stitchable ]] half4 sloshRing(float2 position, half4 color, float2 size, float time, float progress, float thickness,
                                 half4 c1h, half4 c2h, half4 c3h, half4 c4h, half4 c5h) {
    if (progress <= 0.002) { return half4(0.0); }
    float2 centre = size * 0.5;
    float R = min(size.x, size.y) * 0.5;
    float inner = R - thickness;
    float2 d = position - centre;
    float r = length(d);
    float band = smoothstep(inner - 0.75, inner + 0.75, r) * (1.0 - smoothstep(R - 0.75, R + 0.75, r));
    if (band <= 0.001) { return half4(0.0); }
    float a = atan2(d.x, -d.y);                // 0 at the top, +π/2 at the right (clockwise, y down)
    float u = a / 6.2831853;
    if (u < 0.0) { u += 1.0; }
    float v = clamp((r - inner) / max(thickness, 1.0), 0.0, 1.0);
    half4 s = sloshSample(float2(u, v), time, progress, float3(c1h.rgb), float3(c2h.rgb), float3(c3h.rgb), float3(c4h.rgb), float3(c5h.rgb));
    return s * half(band);
}
