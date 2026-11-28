/*
 * sharp-shimmerless-2-core
 * Author: zadpos (analytical single-tap core & linear-light band-limiting)
 * License: Public domain
 *
 * Unified analytical shimmerless scaler using a single hardware bilinear fetch
 * with zero fragment divisions. Supports exact Box, C1 Tent, and Raised-Cosine
 * (Hann) partition-of-unity kernels, plus optional linear-to-sRGB output encoding
 * with float-FBO canary detection (fails loud in solid magenta if a legacy GL
 * driver silently fell back to an 8-bit clamped intermediate FBO).
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
COMPAT_VARYING COMPAT_PRECISION vec2 use_smooth;
#if USE_SPLIT_FP16
COMPAT_VARYING COMPAT_PRECISION vec2 scale_hi;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_mid;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_lo;
COMPAT_VARYING COMPAT_PRECISION vec2 raw_scale_v;
COMPAT_VARYING COMPAT_PRECISION vec2 half_in_v;
COMPAT_VARYING COMPAT_PRECISION vec2 center_err_v;
#endif

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
#if defined(GL_ES)
    // GLES 2.0 vertex shaders always support highp even without fragment highp.
    highp vec2 out_hp = OutputSize;
    highp vec2 in_hp = InputSize;
    highp vec2 tex_hp = TextureSize;
    highp vec2 raw_scale = out_hp / in_hp;
    highp vec2 pixel_hp = TexCoord.xy * out_hp * tex_hp / in_hp;
    invscale = in_hp / out_hp;
    invTextureSize = vec2(1.0) / tex_hp;
#else
    vec2 out_hp = OutputSize;
    vec2 in_hp = InputSize;
    vec2 raw_scale = OutputSize / InputSize;
    vec2 pixel_hp = TexCoord.xy * OutputSize * TextureSize / InputSize;
    invscale = InputSize / OutputSize;
    invTextureSize = vec2(1.0) / TextureSize;
#endif
    scale = max(raw_scale, vec2(1.0));
#if USE_SPLIT_FP16
    // Center pixel around half_out so pixel centers (k + 0.5) stay <= 1024 in binary16
    // (0.5 ULP up to 2048 px wide), avoiding rounding 1245.5 -> 1246 before floor().
    vec2 half_out = floor(0.5 * out_hp);
    vec2 half_in = floor(0.5 * in_hp);
    pixel = pixel_hp - half_out;
    half_in_v = half_in;
    center_err_v = half_out - half_in * raw_scale;

    // Split raw_scale into exact power-of-2 slices so mc * raw_scale stays exact in FP16 fragments.
    vec2 qstep = mix(vec2(8.0), vec2(4.0), step(vec2(8.0), raw_scale));
    vec2 s_hi = floor(raw_scale * qstep) / qstep;
    vec2 rem = raw_scale - s_hi;
    vec2 s_mid = floor(rem * 8192.0 + 0.5) / 8192.0;
    scale_hi = s_hi;
    scale_mid = s_mid;
    scale_lo = rem - s_mid;
    raw_scale_v = raw_scale;
#else
    pixel = pixel_hp;
#endif

    // Width-2 Tent/Hann fits inside 1 texel (1 bilinear fetch) iff scale >= 2.0.
    vec2 is_int_axis = step(abs(raw_scale - floor(raw_scale + 0.5)), vec2(0.001));
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
// GLSL ES defaults sampler2D to lowp, which crushes linear-light shadow values on float FBOs.
uniform SIZE_PRECISION sampler2D Texture;

COMPAT_VARYING SIZE_PRECISION vec2 pixel;
COMPAT_VARYING SIZE_PRECISION vec2 invscale;
COMPAT_VARYING COMPAT_PRECISION vec2 scale;
COMPAT_VARYING SIZE_PRECISION vec2 invTextureSize;
COMPAT_VARYING COMPAT_PRECISION vec2 use_smooth;
#if USE_SPLIT_FP16
COMPAT_VARYING COMPAT_PRECISION vec2 scale_hi;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_mid;
COMPAT_VARYING COMPAT_PRECISION vec2 scale_lo;
COMPAT_VARYING COMPAT_PRECISION vec2 raw_scale_v;
COMPAT_VARYING COMPAT_PRECISION vec2 half_in_v;
COMPAT_VARYING COMPAT_PRECISION vec2 center_err_v;
#endif

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float FILTER_MODE;
uniform COMPAT_PRECISION float GAMMA_OUT;
#else
#define FILTER_MODE 0.0
#define GAMMA_OUT 0.0
#endif

void main()
{
#if USE_SPLIT_FP16
    // Without fragment highp, centered pixel coordinates keep k + 0.5 exact in binary16
    // up to 2048 px wide, and split-FP16 subtraction avoids 0.125-0.25 texel rounding error.
    COMPAT_PRECISION vec2 kc = floor(pixel);
    COMPAT_PRECISION vec2 tx_c = (kc + center_err_v) * invscale;
    COMPAT_PRECISION vec2 mc = floor(tx_c + 0.5);
    COMPAT_PRECISION vec2 mc_hi = 16.0 * floor(mc * 0.0625);
    COMPAT_PRECISION vec2 mc_lo = mc - mc_hi;
    COMPAT_PRECISION vec2 d = ((((kc - mc_hi * scale_hi) - mc_lo * scale_hi) - mc_hi * scale_mid) - mc_lo * scale_mid) + (0.5 + center_err_v) - mc * scale_lo;
    COMPAT_PRECISION vec2 half_s = 0.5 * raw_scale_v;
    COMPAT_PRECISION vec2 adj = step(half_s, d) - step(d, -half_s);
    mc += adj;
    d -= adj * raw_scale_v;
    COMPAT_PRECISION vec2 m = mc + half_in_v;
#else
    // Snap to exact output pixel centers to eliminate hardware barycentric interpolation jitter.
    SIZE_PRECISION vec2 texel = (floor(pixel) + 0.5) * invscale;
    SIZE_PRECISION vec2 m = floor(texel + 0.5);
    COMPAT_PRECISION vec2 d = (texel - m) * scale;
#endif
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

#if USE_SPLIT_FP16
    // Keep w separate from large m before multiplying by invTextureSize to preserve FP16 UV precision.
    COMPAT_PRECISION vec2 uv_up = m * invTextureSize + (w - 0.5) * invTextureSize;
    COMPAT_PRECISION vec2 uv_dn = (half_in_v + tx_c + 0.5 * invscale) * invTextureSize;
    COMPAT_PRECISION vec2 uv = mix(uv_dn, uv_up, step(vec2(1.0), raw_scale_v));
    uv = clamp(uv, vec2(0.5) * invTextureSize, (InputSize - vec2(0.5)) * invTextureSize);
    SIZE_PRECISION vec4 sample_rgba = COMPAT_TEXTURE(Texture, uv);
#else
    // Prevent sampling padded texels outside the active game image.
    SIZE_PRECISION vec2 u = clamp(m - 0.5 + w, vec2(0.5), InputSize - vec2(0.5));
    SIZE_PRECISION vec4 sample_rgba = COMPAT_TEXTURE(Texture, u * invTextureSize);
#endif
    SIZE_PRECISION vec3 color = sample_rgba.rgb;

    if (GAMMA_OUT > 0.5) {
        // Fail loudly in solid magenta if Pass 0's float_framebuffer fell back to clamped 8-bit RGBA8.
        if (sample_rgba.a < 1.5) {
            FragColor = vec4(1.0, 0.0, 1.0, 1.0);
            return;
        }
        color = max(color, vec3(0.0));
        if (GAMMA_OUT < 1.5) {
            color = sqrt(color);
        } else {
            SIZE_PRECISION vec3 lo = color * 12.92;
            SIZE_PRECISION vec3 hi = 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055;
            color = mix(hi, lo, step(color, vec3(0.0031308)));
        }
    }

    FragColor = vec4(color, 1.0);
}
#endif
