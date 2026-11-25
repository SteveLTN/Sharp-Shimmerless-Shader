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

// Keep coordinate math and sampler highp when supported; mediump fallback otherwise.
#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)
#define SIZE_PRECISION highp
#elif defined(GL_ES)
#define SIZE_PRECISION mediump
#else
#define SIZE_PRECISION
#endif

#if (defined(GL_ES) && !defined(GL_FRAGMENT_PRECISION_HIGH)) || defined(SHIMMERLESS_FORCE_SPLIT_FP16)
#define USE_SPLIT_FP16 1
#else
#define USE_SPLIT_FP16 0
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING SIZE_PRECISION vec2 pixel;
COMPAT_VARYING SIZE_PRECISION vec2 invscale;
COMPAT_VARYING COMPAT_PRECISION vec2 scale;
COMPAT_VARYING SIZE_PRECISION vec2 invTextureSize;
#if USE_SPLIT_FP16
COMPAT_VARYING COMPAT_PRECISION vec2 scale_hi;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_mid;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_lo;
COMPAT_VARYING COMPAT_PRECISION vec2 raw_scale_v;
#endif

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform SIZE_PRECISION vec2 OutputSize;
uniform SIZE_PRECISION vec2 TextureSize;
uniform SIZE_PRECISION vec2 InputSize;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
#if defined(GL_ES)
    highp vec2 out_hp = OutputSize;
    highp vec2 in_hp = InputSize;
    highp vec2 tex_hp = TextureSize;
    highp vec2 raw_scale = out_hp / in_hp;
    pixel = TexCoord.xy * out_hp * tex_hp / in_hp;
    invscale = in_hp / out_hp;
    invTextureSize = vec2(1.0) / tex_hp;
#else
    vec2 raw_scale = OutputSize / InputSize;
    pixel = TexCoord.xy * OutputSize * TextureSize / InputSize;
    invscale = InputSize / OutputSize;
    invTextureSize = vec2(1.0) / TextureSize;
#endif
    scale = max(raw_scale, vec2(1.0));
#if USE_SPLIT_FP16
    vec2 qstep = mix(vec2(8.0), vec2(4.0), step(vec2(8.0), raw_scale));
    vec2 s_hi = floor(raw_scale * qstep) / qstep;
    vec2 rem = raw_scale - s_hi;
    vec2 s_mid = floor(rem * 8192.0 + 0.5) / 8192.0;
    scale_hi = s_hi;
    scale_mid = s_mid;
    scale_lo = rem - s_mid;
    raw_scale_v = raw_scale;
#endif
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

#if (defined(GL_ES) && !defined(GL_FRAGMENT_PRECISION_HIGH)) || defined(SHIMMERLESS_FORCE_SPLIT_FP16)
#define USE_SPLIT_FP16 1
#else
#define USE_SPLIT_FP16 0
#endif

uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform SIZE_PRECISION vec2 OutputSize;
uniform SIZE_PRECISION vec2 TextureSize;
uniform SIZE_PRECISION vec2 InputSize;
uniform SIZE_PRECISION sampler2D Texture;
COMPAT_VARYING SIZE_PRECISION vec2 pixel;
COMPAT_VARYING SIZE_PRECISION vec2 invscale;
COMPAT_VARYING COMPAT_PRECISION vec2 scale;
COMPAT_VARYING SIZE_PRECISION vec2 invTextureSize;
#if USE_SPLIT_FP16
COMPAT_VARYING COMPAT_PRECISION vec2 scale_hi;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_mid;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_lo;
COMPAT_VARYING COMPAT_PRECISION vec2 raw_scale_v;
#endif

void main()
{
#if USE_SPLIT_FP16
    COMPAT_PRECISION vec2 k = floor(pixel);
    COMPAT_PRECISION vec2 tx_rough = (k - 0.5 * OutputSize) * invscale + 0.5 * InputSize;
    COMPAT_PRECISION vec2 m = floor(tx_rough + 0.5);
    COMPAT_PRECISION vec2 m_hi = 16.0 * floor(m * 0.0625);
    COMPAT_PRECISION vec2 m_lo = m - m_hi;
    COMPAT_PRECISION vec2 d = ((((k - m_hi * scale_hi) - m_lo * scale_hi) - m_hi * scale_mid) - m_lo * scale_mid) + 0.5 - m * scale_lo;
    COMPAT_PRECISION vec2 half_s = 0.5 * raw_scale_v;
    COMPAT_PRECISION vec2 adj = step(half_s, d) - step(d, -half_s);
    m += adj;
    d -= adj * raw_scale_v;
    COMPAT_PRECISION vec2 w = clamp(d + 0.5, 0.0, 1.0);
    COMPAT_PRECISION vec2 uv_up = m * invTextureSize + (w - 0.5) * invTextureSize;
    COMPAT_PRECISION vec2 uv_dn = (tx_rough + 0.5 * invscale) * invTextureSize;
    COMPAT_PRECISION vec2 uv = mix(uv_dn, uv_up, step(vec2(1.0), raw_scale_v));
    uv = clamp(uv, vec2(0.5) * invTextureSize, (InputSize - vec2(0.5)) * invTextureSize);
    FragColor = vec4(COMPAT_TEXTURE(Texture, uv).rgb, 1.0);
#else
    // Snap to exact output pixel centers to eliminate hardware barycentric interpolation jitter.
    SIZE_PRECISION vec2 texel = (floor(pixel) + 0.5) * invscale;
    SIZE_PRECISION vec2 m = floor(texel + 0.5);
    COMPAT_PRECISION vec2 w = clamp((texel - m) * scale + 0.5, 0.0, 1.0);
    // Keep the far edge from blending in texels outside the game image.
    SIZE_PRECISION vec2 u = clamp(m - 0.5 + w, vec2(0.5), InputSize - vec2(0.5));
    FragColor = vec4(COMPAT_TEXTURE(Texture, u * invTextureSize).rgb, 1.0);
#endif
}
#endif
