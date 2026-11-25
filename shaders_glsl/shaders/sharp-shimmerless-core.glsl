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
COMPAT_VARYING COMPAT_PRECISION vec2 use_smooth;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform SIZE_PRECISION vec2 OutputSize;
uniform SIZE_PRECISION vec2 TextureSize;
uniform SIZE_PRECISION vec2 InputSize;

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float SNAP_INT_AXES;
#else
#define SNAP_INT_AXES 1.0
#endif

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    SIZE_PRECISION vec2 raw_scale = OutputSize / InputSize;
    pixel = TexCoord.xy * OutputSize * TextureSize / InputSize;
    invscale = InputSize / OutputSize;
    scale = max(raw_scale, vec2(1.0));
    invTextureSize = vec2(1.0) / TextureSize;

    // Width-2 Tent/Hann fits inside 1 texel (1 bilinear fetch) iff scale >= 2.0.
    SIZE_PRECISION vec2 is_int_axis = step(abs(raw_scale - floor(raw_scale + 0.5)), vec2(0.001));
    use_smooth = step(vec2(1.999), raw_scale) * (vec2(1.0) - SNAP_INT_AXES * is_int_axis);
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
COMPAT_VARYING COMPAT_PRECISION vec2 use_smooth;

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float FILTER_MODE;
uniform COMPAT_PRECISION float GAMMA_OUT;
#else
#define FILTER_MODE 0.0
#define GAMMA_OUT 0.0
#endif

void main()
{
    // Snap to exact output pixel centers to eliminate hardware barycentric interpolation jitter.
#if defined(GL_ES) && !defined(GL_FRAGMENT_PRECISION_HIGH)
    SIZE_PRECISION vec2 texel = (floor(pixel) + 0.5 - 0.5 * OutputSize) * invscale + 0.5 * InputSize;
#else
    SIZE_PRECISION vec2 texel = (floor(pixel) + 0.5) * invscale;
#endif
    SIZE_PRECISION vec2 m = floor(texel + 0.5);
    COMPAT_PRECISION vec2 d = (texel - m) * scale;
    COMPAT_PRECISION vec2 w_box = clamp(d + 0.5, 0.0, 1.0);
    COMPAT_PRECISION vec2 w = w_box;

    if (FILTER_MODE > 0.5) {
        COMPAT_PRECISION vec2 ds = clamp(d, -1.0, 1.0);
        COMPAT_PRECISION vec2 w_smooth;
        if (FILTER_MODE < 1.5) {
            // Exact CDF of width-2 triangle (Tent) filter: -26 dB sidelobes, exact partition of unity.
            w_smooth = 0.5 + ds - 0.5 * ds * abs(ds);
        } else {
            // Exact CDF of width-2 Raised-Cosine (Hann) filter: -31.5 dB sidelobes.
            w_smooth = 0.5 * (1.0 + ds + sin(3.14159265 * ds) * 0.31830989);
        }
        w = mix(w_box, w_smooth, use_smooth);
    }

    // Prevent sampling padded texels outside the active game image.
    SIZE_PRECISION vec2 u = clamp(m - 0.5 + w, vec2(0.5), InputSize - vec2(0.5));
    COMPAT_PRECISION vec3 color = COMPAT_TEXTURE(Texture, u * invTextureSize).rgb;

    if (GAMMA_OUT > 0.5) {
        color = max(color, vec3(0.0));
        if (GAMMA_OUT < 1.5) {
            color = sqrt(color);
        } else {
            COMPAT_PRECISION vec3 lo = color * 12.92;
            COMPAT_PRECISION vec3 hi = 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055;
            color = mix(hi, lo, step(color, vec3(0.0031308)));
        }
    }

    FragColor = vec4(color, 1.0);
}
#endif
