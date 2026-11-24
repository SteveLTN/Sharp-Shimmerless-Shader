/*
 * sharp-shimmerless
 * Author: zadpos
 * License: Public domain
 * 
 * A retro gaming shader for sharpest pixels with no aliasing/shimmering.
 * Instead of pixels as point samples, this shader considers pixels as
 * ideal rectangles forming a grid, and interpolates pixel by calculating
 * the surface area an input pixel would occupy on an output pixel.
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

// Scale factors that fp16 can't store exactly misplace pixel edges (issue #4).
// GL_FRAGMENT_PRECISION_HIGH is visible to both stages, so the uniform precisions match at link time.
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
COMPAT_VARYING vec2 pixel;

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

// Scale factors that fp16 can't store exactly misplace pixel edges (issue #4).
// GL_FRAGMENT_PRECISION_HIGH is visible to both stages, so the uniform precisions match at link time.
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
COMPAT_VARYING vec2 pixel;

void main()
{
    // Measure both edges in source coordinates so texel selection and blending agree.
#if defined(GL_ES) && !defined(GL_FRAGMENT_PRECISION_HIGH)
    // pixel * InputSize can exceed the fp16 maximum (65504), so scale by a ratio instead.
    // Its rounding error grows with distance from the anchor; anchoring at the center
    // splits that drift evenly between opposite edges.
    vec2 invscale = InputSize / OutputSize;
    vec2 center_out = 0.5 * OutputSize;
    vec2 center_in = 0.5 * InputSize;
    vec2 pixel_tl = (floor(pixel) - center_out) * invscale + center_in;
    vec2 pixel_br = (ceil(pixel) - center_out) * invscale + center_in;
#else
    // Multiplying before dividing keeps the rounding error from growing across the screen.
    vec2 pixel_tl = floor(pixel) * InputSize / OutputSize;
    vec2 pixel_br = ceil(pixel) * InputSize / OutputSize;
#endif
    vec2 texel_tl = floor(pixel_tl);
    vec2 texel_br = floor(pixel_br);

    vec2 same_texel = step(texel_br, texel_tl);
    // Avoid dividing by zero if the two edges round to the same coordinate.
    vec2 width = mix(pixel_br - pixel_tl, vec2(1.0), same_texel);
    vec2 weight_br = mix(fract(pixel_br) / width, vec2(1.0), same_texel);
    vec2 mod_texel = texel_br - 0.5 + weight_br;
    // Keep the far edge from blending in texels outside the game image.
    mod_texel = clamp(mod_texel, vec2(0.5), InputSize - vec2(0.5));

    FragColor = vec4(COMPAT_TEXTURE(Texture, mod_texel / TextureSize).rgb, 1.0);
} 
#endif
