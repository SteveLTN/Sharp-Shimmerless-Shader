#version 450

/*
 * sharp-shimmerless-core
 * Author: zadpos (analytical single-tap core & linear-light band-limiting)
 * License: Public domain
 *
 * Unified analytical shimmerless scaler using a single hardware bilinear fetch
 * with zero fragment divisions. Supports exact Box, C1 Tent, and Raised-Cosine
 * (Hann) partition-of-unity kernels, plus optional linear-to-sRGB output encoding.
 */

#pragma parameter FILTER_MODE "Filter (0=Box, 1=Tent, 2=Hann)" 0.0 0.0 2.0 1.0
#pragma parameter GAMMA_OUT "Gamma Output (0=Off, 1=Fast 2.0, 2=Exact sRGB)" 0.0 0.0 2.0 1.0
#pragma parameter SNAP_INT_AXES "Snap Exact Integer Axes to Box" 1.0 0.0 1.0 1.0

layout(push_constant) uniform Push
{
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    uint FrameCount;
    float FILTER_MODE;
    float GAMMA_OUT;
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
layout(location = 2) out vec2 scale;
layout(location = 3) out vec2 use_smooth;

void main()
{
    gl_Position = global.MVP * Position;
    vec2 raw_scale = params.OutputSize.xy * params.SourceSize.zw;
    pixel = TexCoord * params.OutputSize.xy;
    invscale = params.SourceSize.xy * params.OutputSize.zw;
    scale = max(raw_scale, vec2(1.0));

    // Width-2 Tent/Hann fits inside 1 texel (1 bilinear fetch) iff scale >= 2.0.
    vec2 is_int_axis = step(abs(raw_scale - floor(raw_scale + 0.5)), vec2(0.001));
    use_smooth = step(vec2(1.999), raw_scale) * (vec2(1.0) - params.SNAP_INT_AXES * is_int_axis);
}

#pragma stage fragment
layout(location = 0) in vec2 pixel;
layout(location = 1) in vec2 invscale;
layout(location = 2) in vec2 scale;
layout(location = 3) in vec2 use_smooth;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

void main()
{
    // Snap to exact output pixel centers to eliminate hardware barycentric interpolation jitter.
    vec2 texel = (floor(pixel) + 0.5) * invscale;
    vec2 m = floor(texel + 0.5);
    vec2 d = (texel - m) * scale;
    vec2 w_box = clamp(d + 0.5, 0.0, 1.0);
    vec2 w = w_box;

    if (params.FILTER_MODE > 0.5) {
        vec2 ds = clamp(d, -1.0, 1.0);
        vec2 w_smooth;
        if (params.FILTER_MODE < 1.5) {
            // Exact CDF of width-2 triangle (Tent) filter: -26 dB sidelobes, exact partition of unity.
            w_smooth = 0.5 + ds - 0.5 * ds * abs(ds);
        } else {
            // Exact CDF of width-2 Raised-Cosine (Hann) filter: -31.5 dB sidelobes.
            w_smooth = 0.5 * (1.0 + ds + sin(3.14159265 * ds) * 0.31830989);
        }
        w = mix(w_box, w_smooth, use_smooth);
    }

    vec2 u = clamp(m - 0.5 + w, vec2(0.5), params.SourceSize.xy - vec2(0.5));
    vec3 color = texture(Source, u * params.SourceSize.zw).rgb;

    if (params.GAMMA_OUT > 0.5) {
        color = max(color, vec3(0.0));
        if (params.GAMMA_OUT < 1.5) {
            color = sqrt(color);
        } else {
            vec3 lo = color * 12.92;
            vec3 hi = 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055;
            color = mix(hi, lo, step(color, vec3(0.0031308)));
        }
    }

    FragColor = vec4(color, 1.0);
}
