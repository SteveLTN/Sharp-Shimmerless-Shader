/*
 * sharp-shimmerless-2-8bfbo-safe
 * Author: zadpos (analytical single-pass linear-light adaptive core)
 * License: Public domain
 *
 * Single-pass linear-light shimmerless scaler that requires no intermediate
 * floating-point framebuffer (immune to legacy GL 8-bit FBO fallback).
 * Uses GL_NEAREST with adaptive 1/2/4-tap sampling: interior pixels perform
 * 1 fetch with zero gamma math, 1D edges perform 2 fetches, and only 2D
 * corners perform 4 fetches.
 */

#pragma parameter FILTER_MODE "Filter (0=Box, 1=Tent, 2=Hann)" 0.0 0.0 2.0 1.0
#pragma parameter GAMMA_MODE "Gamma Curve (0=Off/sRGB, 1=Fast 2.0, 2=Exact sRGB)" 1.0 0.0 2.0 1.0
#pragma parameter SNAP_INT_AXES "Snap Exact Integer Axes to Box" 1.0 0.0 1.0 1.0

#if defined(VERTEX)

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

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

#if (defined(GL_ES) && !defined(GL_FRAGMENT_PRECISION_HIGH)) || defined(SHIMMERLESS_FORCE_SPLIT_FP16)
#define USE_SPLIT_FP16 1
#else
#define USE_SPLIT_FP16 0
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_ATTRIBUTE vec4 TexCoord;
#if USE_SPLIT_FP16
// Pack into 5 vec4 slots so legacy GLES 2.0 drivers without cross-varying packing stay <= 8 slots.
COMPAT_VARYING SIZE_PRECISION vec4 v_pix_inv;
COMPAT_VARYING COMPAT_PRECISION vec4 v_tex_smooth;
COMPAT_VARYING COMPAT_PRECISION vec4 v_scale_hi_mid;
COMPAT_VARYING COMPAT_PRECISION vec4 v_scale_lo_raw;
COMPAT_VARYING COMPAT_PRECISION vec4 v_half_err;
#else
COMPAT_VARYING SIZE_PRECISION vec2 pixel;
COMPAT_VARYING SIZE_PRECISION vec2 invscale;
COMPAT_VARYING SIZE_PRECISION vec2 raw_scale_v;
COMPAT_VARYING SIZE_PRECISION vec2 invTextureSize;
COMPAT_VARYING COMPAT_PRECISION vec2 use_smooth;
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
    highp vec2 invscale_hp = in_hp / out_hp;
    highp vec2 invTex_hp = vec2(1.0) / tex_hp;
#else
    vec2 out_hp = OutputSize;
    vec2 in_hp = InputSize;
    vec2 raw_scale = OutputSize / InputSize;
    vec2 pixel_hp = TexCoord.xy * OutputSize * TextureSize / InputSize;
    vec2 invscale_hp = InputSize / OutputSize;
    vec2 invTex_hp = vec2(1.0) / TextureSize;
#endif

    // Width-2 Tent/Hann fits inside a 2x2 texel neighborhood iff scale >= 2.0.
    vec2 is_int_axis = step(abs(raw_scale - floor(raw_scale + 0.5)), vec2(0.001));
    vec2 smooth_mask = step(vec2(1.999), raw_scale) * (vec2(1.0) - SNAP_INT_AXES * is_int_axis);

#if USE_SPLIT_FP16
    vec2 half_out = floor(0.5 * out_hp);
    vec2 half_in = floor(0.5 * in_hp);
    vec2 center_err = half_out - half_in * raw_scale;

    vec2 qstep = mix(vec2(8.0), vec2(4.0), step(vec2(8.0), raw_scale));
    vec2 s_hi = floor(raw_scale * qstep) / qstep;
    vec2 rem = raw_scale - s_hi;
    vec2 s_mid = floor(rem * 8192.0 + 0.5) / 8192.0;

    v_pix_inv = vec4(pixel_hp - half_out, invscale_hp);
    v_tex_smooth = vec4(invTex_hp, smooth_mask);
    v_scale_hi_mid = vec4(s_hi, s_mid);
    v_scale_lo_raw = vec4(rem - s_mid, raw_scale);
    v_half_err = vec4(half_in, center_err);
#else
    pixel = pixel_hp;
    invscale = invscale_hp;
    raw_scale_v = raw_scale;
    invTextureSize = invTex_hp;
    use_smooth = smooth_mask;
#endif
}

#elif defined(FRAGMENT)

// Precision declarations must precede any float/vec4 output declarations in GLSL ES 3.00.
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

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
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
// GLSL ES defaults sampler2D to lowp; match fragment precision for clean reads.
uniform SIZE_PRECISION sampler2D Texture;

#if USE_SPLIT_FP16
COMPAT_VARYING SIZE_PRECISION vec4 v_pix_inv;
COMPAT_VARYING COMPAT_PRECISION vec4 v_tex_smooth;
COMPAT_VARYING COMPAT_PRECISION vec4 v_scale_hi_mid;
COMPAT_VARYING COMPAT_PRECISION vec4 v_scale_lo_raw;
COMPAT_VARYING COMPAT_PRECISION vec4 v_half_err;
#else
COMPAT_VARYING SIZE_PRECISION vec2 pixel;
COMPAT_VARYING SIZE_PRECISION vec2 invscale;
COMPAT_VARYING SIZE_PRECISION vec2 raw_scale_v;
COMPAT_VARYING SIZE_PRECISION vec2 invTextureSize;
COMPAT_VARYING COMPAT_PRECISION vec2 use_smooth;
#endif

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float FILTER_MODE;
uniform COMPAT_PRECISION float GAMMA_MODE;
#else
#define FILTER_MODE 0.0
#define GAMMA_MODE 1.0
#endif

SIZE_PRECISION vec3 to_linear(SIZE_PRECISION vec3 c)
{
    if (GAMMA_MODE < 0.5) {
        return c;
    }
    if (GAMMA_MODE < 1.5) {
        return c * c;
    }
    SIZE_PRECISION vec3 lo = c / 12.92;
    SIZE_PRECISION vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(hi, lo, step(c, vec3(0.04045)));
}

SIZE_PRECISION vec3 from_linear(SIZE_PRECISION vec3 c)
{
    if (GAMMA_MODE < 0.5) {
        return c;
    }
    c = max(c, vec3(0.0));
    if (GAMMA_MODE < 1.5) {
        return sqrt(c);
    }
    SIZE_PRECISION vec3 lo = c * 12.92;
    // Clamp base at the piecewise threshold so pow(0.0, ...) never generates NaN on non-IEEE GPUs.
    SIZE_PRECISION vec3 hi = 1.055 * pow(max(c, vec3(0.0031308)), vec3(1.0 / 2.4)) - 0.055;
    return mix(hi, lo, step(c, vec3(0.0031308)));
}

void main()
{
#if USE_SPLIT_FP16
    COMPAT_PRECISION vec2 kc = floor(v_pix_inv.xy);
    COMPAT_PRECISION vec2 invs = v_pix_inv.zw;
    COMPAT_PRECISION vec2 invTex = v_tex_smooth.xy;
    COMPAT_PRECISION vec2 smooth_mask = v_tex_smooth.zw;
    COMPAT_PRECISION vec2 s_hi = v_scale_hi_mid.xy;
    COMPAT_PRECISION vec2 s_mid = v_scale_hi_mid.zw;
    COMPAT_PRECISION vec2 s_lo = v_scale_lo_raw.xy;
    COMPAT_PRECISION vec2 r_scale = v_scale_lo_raw.zw;
    COMPAT_PRECISION vec2 half_in = v_half_err.xy;
    COMPAT_PRECISION vec2 c_err = v_half_err.zw;

    COMPAT_PRECISION vec2 tx_c = (kc + c_err) * invs;
    COMPAT_PRECISION vec2 mc = floor(tx_c + 0.5);
    COMPAT_PRECISION vec2 mc_hi = 16.0 * floor(mc * 0.0625);
    COMPAT_PRECISION vec2 mc_lo = mc - mc_hi;
    COMPAT_PRECISION vec2 d = ((((kc - mc_hi * s_hi) - mc_lo * s_hi) - mc_hi * s_mid) - mc_lo * s_mid) + (0.5 + c_err) - mc * s_lo;
    COMPAT_PRECISION vec2 half_s = 0.5 * r_scale;
    COMPAT_PRECISION vec2 adj = step(half_s, d) - step(d, -half_s);
    mc += adj;
    d -= adj * r_scale;
    COMPAT_PRECISION vec2 m = mc + half_in;

    // Keep downscale floor/diff centered before adding half_in to preserve FP16 mantissa bits.
    COMPAT_PRECISION vec2 is_up = step(vec2(1.0), r_scale);
    COMPAT_PRECISION vec2 tx_c_dn = tx_c + 0.5 * invs;
    COMPAT_PRECISION vec2 mc_dn = floor(tx_c_dn + 0.5);
    COMPAT_PRECISION vec2 m_dn = mc_dn + half_in;
    COMPAT_PRECISION vec2 d_dn = tx_c_dn - mc_dn;
    m = mix(m_dn, m, is_up);
    d = mix(d_dn, d, is_up);
#else
    // Evaluate upscale distance directly in output space and recover exact integer/half-integer
    // scales from barycentric varying interpolation noise (GLSL 120 / ES 1.00 lack `flat`).
    SIZE_PRECISION vec2 k_center = floor(pixel) + 0.5;
    SIZE_PRECISION vec2 texel = k_center * invscale;
    SIZE_PRECISION vec2 m = floor(texel + 0.5);
    SIZE_PRECISION vec2 rs_snap = floor(raw_scale_v * 2.0 + 0.5) * 0.5;
    SIZE_PRECISION vec2 r_scale = mix(raw_scale_v, rs_snap, step(abs(raw_scale_v - rs_snap), vec2(1e-5)));
    COMPAT_PRECISION vec2 d = mix(texel - m, k_center - m * r_scale, step(vec2(1.0), r_scale));
    SIZE_PRECISION vec2 invTex = invTextureSize;
    COMPAT_PRECISION vec2 smooth_mask = use_smooth;
#endif
    // True fractional box weights are >= 1/InputSize (~4e-3 at 240p); snap <1e-4 FP32 noise to exact 0/1.
    COMPAT_PRECISION vec2 w_box = clamp(d + 0.5, 0.0, 1.0);
    w_box = mix(w_box, step(vec2(0.5), w_box), step(vec2(0.4999), abs(w_box - 0.5)));
    COMPAT_PRECISION vec2 w = w_box;

    if (FILTER_MODE > 0.5 && (smooth_mask.x + smooth_mask.y) > 0.5) {
        COMPAT_PRECISION vec2 ds = clamp(d, -1.0, 1.0);
        COMPAT_PRECISION vec2 w_smooth;
        if (FILTER_MODE < 1.5) {
            w_smooth = 0.5 + ds - 0.5 * ds * abs(ds);
        } else {
            w_smooth = 0.5 * (1.0 + ds + sin(3.14159265 * ds) * 0.31830989);
            // Force exact 0/1 outside [-1, 1] so interior pixels skip redundant blending.
            w_smooth = mix(clamp(w_smooth, 0.0, 1.0), step(vec2(0.0), ds), step(vec2(1.0), abs(d)));
        }
        w = mix(w_box, w_smooth, smooth_mask);
    }

    SIZE_PRECISION vec2 u0 = clamp(m - 0.5, vec2(0.5), InputSize - vec2(0.5));
    SIZE_PRECISION vec2 u1 = clamp(m + 0.5, vec2(0.5), InputSize - vec2(0.5));
    SIZE_PRECISION vec2 uv0 = u0 * invTex;
    SIZE_PRECISION vec2 uv1 = u1 * invTex;

    bool blend_x = (w.x > 0.0) && (w.x < 1.0) && (uv0.x != uv1.x);
    bool blend_y = (w.y > 0.0) && (w.y < 1.0) && (uv0.y != uv1.y);

    SIZE_PRECISION vec3 color;
    if (!blend_x && !blend_y) {
        SIZE_PRECISION vec2 uv = vec2(w.x >= 0.5 ? uv1.x : uv0.x, w.y >= 0.5 ? uv1.y : uv0.y);
        color = COMPAT_TEXTURE(Texture, uv).rgb;
    } else if (blend_x && !blend_y) {
        SIZE_PRECISION float uy = w.y >= 0.5 ? uv1.y : uv0.y;
        SIZE_PRECISION vec3 t0 = COMPAT_TEXTURE(Texture, vec2(uv0.x, uy)).rgb;
        SIZE_PRECISION vec3 t1 = COMPAT_TEXTURE(Texture, vec2(uv1.x, uy)).rgb;
        color = from_linear(mix(to_linear(t0), to_linear(t1), w.x));
    } else if (!blend_x && blend_y) {
        SIZE_PRECISION float ux = w.x >= 0.5 ? uv1.x : uv0.x;
        SIZE_PRECISION vec3 t0 = COMPAT_TEXTURE(Texture, vec2(ux, uv0.y)).rgb;
        SIZE_PRECISION vec3 t1 = COMPAT_TEXTURE(Texture, vec2(ux, uv1.y)).rgb;
        color = from_linear(mix(to_linear(t0), to_linear(t1), w.y));
    } else {
        SIZE_PRECISION vec3 t00 = COMPAT_TEXTURE(Texture, vec2(uv0.x, uv0.y)).rgb;
        SIZE_PRECISION vec3 t10 = COMPAT_TEXTURE(Texture, vec2(uv1.x, uv0.y)).rgb;
        SIZE_PRECISION vec3 t01 = COMPAT_TEXTURE(Texture, vec2(uv0.x, uv1.y)).rgb;
        SIZE_PRECISION vec3 t11 = COMPAT_TEXTURE(Texture, vec2(uv1.x, uv1.y)).rgb;
        SIZE_PRECISION vec3 cx0 = mix(to_linear(t00), to_linear(t10), w.x);
        SIZE_PRECISION vec3 cx1 = mix(to_linear(t01), to_linear(t11), w.x);
        color = from_linear(mix(cx0, cx1, w.y));
    }

    FragColor = vec4(color, 1.0);
}
#endif
