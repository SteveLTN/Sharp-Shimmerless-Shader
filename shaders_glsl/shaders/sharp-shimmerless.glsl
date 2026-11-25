/*
 * sharp-shimmerless
 * Author: zadpos
 * License: Public domain
 *
 * A retro gaming shader for sharpest pixels with no aliasing/shimmering.
 * Evaluates the exact 2D area-averaged box filter analytically in a single
 * hardware bilinear texture fetch with zero fragment divisions.
 */

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

// Keep coordinate math highp when supported so scale rounding never drifts across the screen.
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
COMPAT_VARYING SIZE_PRECISION vec2 pixel;
COMPAT_VARYING SIZE_PRECISION vec2 invscale;
COMPAT_VARYING COMPAT_PRECISION vec2 scale;
COMPAT_VARYING SIZE_PRECISION vec2 invTextureSize;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform SIZE_PRECISION vec2 OutputSize;
uniform SIZE_PRECISION vec2 TextureSize;
uniform SIZE_PRECISION vec2 InputSize;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    pixel = TexCoord.xy * OutputSize * TextureSize / InputSize;
    invscale = InputSize / OutputSize;
    scale = max(OutputSize / InputSize, vec2(1.0));
    invTextureSize = vec2(1.0) / TextureSize;
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
uniform sampler2D Texture;
COMPAT_VARYING SIZE_PRECISION vec2 pixel;
COMPAT_VARYING SIZE_PRECISION vec2 invscale;
COMPAT_VARYING COMPAT_PRECISION vec2 scale;
COMPAT_VARYING SIZE_PRECISION vec2 invTextureSize;

void main()
{
    // Snap to exact output pixel centers to eliminate hardware barycentric interpolation jitter.
#if defined(GL_ES) && !defined(GL_FRAGMENT_PRECISION_HIGH)
    SIZE_PRECISION vec2 texel = (floor(pixel) + 0.5 - 0.5 * OutputSize) * invscale + 0.5 * InputSize;
#else
    SIZE_PRECISION vec2 texel = (floor(pixel) + 0.5) * invscale;
#endif
    SIZE_PRECISION vec2 m = floor(texel + 0.5);
    COMPAT_PRECISION vec2 w = clamp((texel - m) * scale + 0.5, 0.0, 1.0);
    // Keep the far edge from blending in texels outside the game image.
    SIZE_PRECISION vec2 u = clamp(m - 0.5 + w, vec2(0.5), InputSize - vec2(0.5));

    FragColor = vec4(COMPAT_TEXTURE(Texture, u * invTextureSize).rgb, 1.0);
}
#endif
