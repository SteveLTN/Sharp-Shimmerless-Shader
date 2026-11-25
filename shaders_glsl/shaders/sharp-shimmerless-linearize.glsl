/*
 * sharp-shimmerless-linearize
 * License: Public domain
 *
 * Pass 0 (1x source resolution): converts gamma-encoded RGB input into linear light
 * for hardware-accelerated bilinear blending in sharp-shimmerless-core.
 */

#pragma parameter GAMMA_MODE "Gamma Curve (0=Fast 2.0, 1=Exact sRGB)" 0.0 0.0 1.0 1.0

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)
#define SIZE_PRECISION highp
#elif defined(GL_ES)
#define SIZE_PRECISION mediump
#else
#define SIZE_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING SIZE_PRECISION vec2 vTexCoord;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform SIZE_PRECISION vec2 OutputSize;
uniform SIZE_PRECISION vec2 TextureSize;
uniform SIZE_PRECISION vec2 InputSize;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    vTexCoord = TexCoord.xy;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)
#define SIZE_PRECISION highp
#elif defined(GL_ES)
#define SIZE_PRECISION mediump
#else
#define SIZE_PRECISION
#endif

uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform SIZE_PRECISION vec2 OutputSize;
uniform SIZE_PRECISION vec2 TextureSize;
uniform SIZE_PRECISION vec2 InputSize;
// GLSL ES defaults sampler2D to lowp; match fragment precision to preserve linear shadow detail.
uniform SIZE_PRECISION sampler2D Texture;
COMPAT_VARYING SIZE_PRECISION vec2 vTexCoord;

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float GAMMA_MODE;
#else
#define GAMMA_MODE 0.0
#endif

void main()
{
    SIZE_PRECISION vec3 c = COMPAT_TEXTURE(Texture, vTexCoord).rgb;
    SIZE_PRECISION vec3 lin;
    if (GAMMA_MODE < 0.5) {
        lin = c * c;
    } else {
        SIZE_PRECISION vec3 lo = c / 12.92;
        SIZE_PRECISION vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
        lin = mix(hi, lo, step(c, vec3(0.04045)));
    }
    FragColor = vec4(lin, 1.0);
}
#endif
