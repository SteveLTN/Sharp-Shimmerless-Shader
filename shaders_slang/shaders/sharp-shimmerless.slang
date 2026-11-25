#version 450

/*
 * sharp-shimmerless
 * Author: zadpos
 * License: Public domain
 *
 * A retro gaming shader for sharpest pixels with no aliasing/shimmering.
 * Evaluates the exact 2D area-averaged box filter analytically in a single
 * hardware bilinear texture fetch with zero fragment divisions.
 */

layout(push_constant) uniform Push
{
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    uint FrameCount;
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

void main()
{
    gl_Position = global.MVP * Position;
    pixel = TexCoord * params.OutputSize.xy;
    invscale = params.SourceSize.xy * params.OutputSize.zw;
    scale = max(params.OutputSize.xy * params.SourceSize.zw, vec2(1.0));
}

#pragma stage fragment
layout(location = 0) in vec2 pixel;
layout(location = 1) in vec2 invscale;
layout(location = 2) in vec2 scale;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

void main()
{
    // Snap to exact output pixel centers to eliminate hardware barycentric interpolation jitter.
    vec2 texel = (floor(pixel) + 0.5) * invscale;
    vec2 m = floor(texel + 0.5);
    vec2 w = clamp((texel - m) * scale + 0.5, 0.0, 1.0);
    vec2 u = clamp(m - 0.5 + w, vec2(0.5), params.SourceSize.xy - vec2(0.5));
    FragColor = vec4(texture(Source, u * params.SourceSize.zw).rgb, 1.0);
}
