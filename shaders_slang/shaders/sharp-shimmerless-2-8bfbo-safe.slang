#version 450

/*
 * sharp-shimmerless-2-8bfbo-safe
 * Author: zadpos (analytical single-pass linear-light adaptive core)
 * License: Public domain
 *
 * Single-pass linear-light shimmerless scaler that requires no intermediate
 * floating-point framebuffer. Uses GL_NEAREST with adaptive 1/2/4-tap
 * sampling: interior pixels perform 1 fetch with zero gamma math, 1D edges
 * perform 2 fetches, and only 2D corners perform 4 fetches.
 */

#pragma parameter FILTER_MODE "Filter (0=Box, 1=Tent, 2=Hann)" 0.0 0.0 2.0 1.0
#pragma parameter GAMMA_MODE "Gamma Curve (0=Off/sRGB, 1=Fast 2.0, 2=Exact sRGB)" 1.0 0.0 2.0 1.0
#pragma parameter SNAP_INT_AXES "Snap Exact Integer Axes to Box" 1.0 0.0 1.0 1.0

layout(push_constant) uniform Push
{
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    uint FrameCount;
    float FILTER_MODE;
    float GAMMA_MODE;
    float SNAP_INT_AXES;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 pixel;
layout(location = 1) out vec2 invscale;
layout(location = 2) flat out vec2 raw_scale_v;
layout(location = 3) flat out vec2 use_smooth;

void main()
{
    gl_Position = global.MVP * Position;
    vec2 raw_scale = params.OutputSize.xy * params.SourceSize.zw;
    pixel = TexCoord * params.OutputSize.xy;
    invscale = params.SourceSize.xy * params.OutputSize.zw;
    raw_scale_v = raw_scale;

    // Width-2 Tent/Hann fits inside a 2x2 texel neighborhood iff scale >= 2.0.
    vec2 is_int_axis = step(abs(raw_scale - floor(raw_scale + 0.5)), vec2(0.001));
    use_smooth = step(vec2(1.999), raw_scale) * (vec2(1.0) - params.SNAP_INT_AXES * is_int_axis);
}

#pragma stage fragment
layout(location = 0) in vec2 pixel;
layout(location = 1) in vec2 invscale;
layout(location = 2) flat in vec2 raw_scale_v;
layout(location = 3) flat in vec2 use_smooth;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

vec3 to_linear(vec3 c)
{
    if (params.GAMMA_MODE < 0.5) {
        return c;
    }
    if (params.GAMMA_MODE < 1.5) {
        return c * c;
    }
    vec3 lo = c / 12.92;
    vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(hi, lo, step(c, vec3(0.04045)));
}

vec3 from_linear(vec3 c)
{
    if (params.GAMMA_MODE < 0.5) {
        return c;
    }
    c = max(c, vec3(0.0));
    if (params.GAMMA_MODE < 1.5) {
        return sqrt(c);
    }
    vec3 lo = c * 12.92;
    // Clamp base at the piecewise threshold so pow(0.0, ...) never generates NaN.
    vec3 hi = 1.055 * pow(max(c, vec3(0.0031308)), vec3(1.0 / 2.4)) - 0.055;
    return mix(hi, lo, step(c, vec3(0.0031308)));
}

void main()
{
    // Evaluate upscale distance directly in output space so integer/half-integer
    // scales hit exact 0/1 weights without invscale rounding leakage.
    vec2 k_center = floor(pixel) + 0.5;
    vec2 texel = k_center * invscale;
    vec2 m = floor(texel + 0.5);
    vec2 d = mix(texel - m, k_center - m * raw_scale_v, step(vec2(1.0), raw_scale_v));
    // True fractional box weights are >= 1/InputSize (~4e-3 at 240p); snap <1e-4 FP32 noise to exact 0/1.
    vec2 w_box = clamp(d + 0.5, 0.0, 1.0);
    w_box = mix(w_box, step(vec2(0.5), w_box), step(vec2(0.4999), abs(w_box - 0.5)));
    vec2 w = w_box;

    if (params.FILTER_MODE > 0.5 && (use_smooth.x + use_smooth.y) > 0.5) {
        vec2 ds = clamp(d, -1.0, 1.0);
        vec2 w_smooth;
        if (params.FILTER_MODE < 1.5) {
            w_smooth = 0.5 + ds - 0.5 * ds * abs(ds);
        } else {
            w_smooth = 0.5 * (1.0 + ds + sin(3.14159265 * ds) * 0.31830989);
            w_smooth = mix(clamp(w_smooth, 0.0, 1.0), step(vec2(0.0), ds), step(vec2(1.0), abs(d)));
        }
        w = mix(w_box, w_smooth, use_smooth);
    }

    vec2 u0 = clamp(m - 0.5, vec2(0.5), params.SourceSize.xy - vec2(0.5));
    vec2 u1 = clamp(m + 0.5, vec2(0.5), params.SourceSize.xy - vec2(0.5));
    vec2 uv0 = u0 * params.SourceSize.zw;
    vec2 uv1 = u1 * params.SourceSize.zw;

    bool blend_x = (w.x > 0.0) && (w.x < 1.0) && (uv0.x != uv1.x);
    bool blend_y = (w.y > 0.0) && (w.y < 1.0) && (uv0.y != uv1.y);

    vec3 color;
    if (!blend_x && !blend_y) {
        vec2 uv = vec2(w.x >= 0.5 ? uv1.x : uv0.x, w.y >= 0.5 ? uv1.y : uv0.y);
        color = texture(Source, uv).rgb;
    } else if (blend_x && !blend_y) {
        float uy = w.y >= 0.5 ? uv1.y : uv0.y;
        vec3 t0 = texture(Source, vec2(uv0.x, uy)).rgb;
        vec3 t1 = texture(Source, vec2(uv1.x, uy)).rgb;
        color = from_linear(mix(to_linear(t0), to_linear(t1), w.x));
    } else if (!blend_x && blend_y) {
        float ux = w.x >= 0.5 ? uv1.x : uv0.x;
        vec3 t0 = texture(Source, vec2(ux, uv0.y)).rgb;
        vec3 t1 = texture(Source, vec2(ux, uv1.y)).rgb;
        color = from_linear(mix(to_linear(t0), to_linear(t1), w.y));
    } else {
        vec3 t00 = texture(Source, vec2(uv0.x, uv0.y)).rgb;
        vec3 t10 = texture(Source, vec2(uv1.x, uv0.y)).rgb;
        vec3 t01 = texture(Source, vec2(uv0.x, uv1.y)).rgb;
        vec3 t11 = texture(Source, vec2(uv1.x, uv1.y)).rgb;
        vec3 cx0 = mix(to_linear(t00), to_linear(t10), w.x);
        vec3 cx1 = mix(to_linear(t01), to_linear(t11), w.x);
        color = from_linear(mix(cx0, cx1, w.y));
    }

    FragColor = vec4(color, 1.0);
}
