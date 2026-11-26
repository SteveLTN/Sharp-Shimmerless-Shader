#version 450

/*
 * sharp-shimmerless-linearize
 * License: Public domain
 *
 * Pass 0 (1x source resolution): converts gamma-encoded RGB input into linear light
 * for hardware-accelerated bilinear blending in sharp-shimmerless-core.
 */

#pragma parameter GAMMA_MODE "Gamma Curve (0=Fast 2.0, 1=Exact sRGB)" 0.0 0.0 1.0 1.0

layout(push_constant) uniform Push
{
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    uint FrameCount;
    float GAMMA_MODE;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

void main()
{
    vec3 c = texture(Source, vTexCoord).rgb;
    vec3 lin;
    if (params.GAMMA_MODE < 0.5) {
        lin = c * c;
    } else {
        vec3 lo = c / 12.92;
        vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
        lin = mix(hi, lo, step(c, vec3(0.04045)));
    }
    // Alpha > 1.0 survives only on unclamped floating-point FBOs; 8-bit UNORM clamps it to 1.0.
    FragColor = vec4(lin, 2.0);
}
