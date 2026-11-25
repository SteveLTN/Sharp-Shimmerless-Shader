# Sharp-Shimmerless-Shader

## A Sharp, Shimmering-free Shader for RetroArch
The Sharp-Shimmerless shader is a shader which guarantees minimum number of interpolated pixels, i.e., the sharpest rectangular pixels possible, while inducing NO aliasing/shimmering.

## Existing Solutions and Their Limitations
There already exist some attempts at achieving both sharp pixels and anti-aliasing, one of them being [sharp-bilinear shaders](https://github.com/rsn8887/Sharp-Bilinear-Shaders).
While they produce reasonably good image on modern high resolution screens, they fall apart on low-resolution screens often found in open-source handhelds.

Below is Cave Story, a 240p game, played on a 320p screen.

<table align=center>
  <thead>
    <tr>
      <th width="34%"></th>
      <th width="32%"></th>
      <th width="34%"></th>
    </tr>
  </thead>
 <tbody>
  <tr>
   <td colspan=3><video src="https://user-images.githubusercontent.com/82881609/214218505-dbb13ff4-fc8d-4621-b225-8309bb418c5c.mp4"></td>
  </tr>
  <tr align=center>
   <td> Sharp-Bilinear </td>
   <td> Sharp-Shimmerless </td>
   <td> Sharp-Bilinear-2x-Prescale </td>
  </tr>
 </tbody>
</table>

Sharp-Bilinear shader on the left side results in a very blurry image.
It is an expected behavior, since what sharp-bilinear shader does is integer pre-scaling followed by bilinear upscaling to screen - when scaling factor is less than 2, integer prescaling would do nothing.
Sharp-Bilinear shader becomes a regular **bilinear filter**.

Sharp-Bilinear-*2x-Prescale* shader on the right side, at first glance, produces a nice-looking, sharp image.
However, when the screen starts to scroll, you can notice vertical lines on the wall are **badly shimmering**.
(Shimmering is also there on Sharp-Bilinear shader, but less noticeable due to the *blurriness*.)

It is a fundamental limitation for any kind of point sampling approach that it treats each pixel as a point with position but no area, whereas in retro gaming we want rectangular pixels.

## A Box Filter
Sharp-Shimmerless shader does not do any kind of point sampling, and instead treats input and output pixels as ideal rectangles, occupying each of their area on the grid that is screen.

It interpolates pixels based on how much area an input pixel would occupy on an output pixel.
* If an output pixel lies entirely on a single input pixel, there is no interpolation for the pixel.
* If an output pixel lies across multiple input pixels, the input pixels are interpolated proportionally to the area they occupy on the output pixel.

Hence, it achieves both minimal number of interpolated pixels and ideal anti aliasing, i.e. **NO SHIMMERING**!

## Presets

Both GLSL (`shaders_glsl/`) and Slang (`shaders_slang/`) ship three main presets built on a shared zero-division analytical core:

* **`sharp-shimmerless`** *(Recommended default)* — 2-pass linear-light box filter. Linearizes at 1× source resolution into a half-float framebuffer so hardware bilinear filtering blends in linear light with a single texture fetch at output resolution, eliminating both geometric and brightness shimmering. Ideal for 640×480 handhelds and general displays.
* **`sharp-shimmerless-smooth-hq`** — 2-pass linear-light $C^1$ band-limited filter (Tent by default, Hann selectable via shader parameters) for high-PPI displays (such as 1024×768 TrimUI Brick, 720p, 1080p+). Automatically snaps exact integer axes (e.g. 256 px → 1024 px = 4×) and scale factors $< 2\times$ back to the box filter.
* **`sharp-shimmerless-fast`** — 1-pass sRGB box filter fallback for legacy GLES 2.0 drivers without linear half-float FBO support or ultra-low-power devices. Uses a single texture fetch and zero fragment divisions, at the cost of sRGB edge darkening on high-contrast seams.

### Color Correction (GBA / GBC)
Core-side color correction (mGBA, Gambatte, SameBoy) outputs standard sRGB prior to shader execution and works seamlessly with all presets. If using shader-side color correction (`gba-color` / `gbc-color`), prepend it at `1x source` *before* `sharp-shimmerless-linearize` rather than after scaling.

### Curvature Shaders
Applies CRT-like curvature.
`-curvature-grid` and `curvature-scanlines` versions combines curvature and grid/scanline effects.

### Grid/Scanlines Shaders
Applies grid or scanline effect.
`-curvature-grid` and `curvature-scanlines` versions combines curvature and grid/scanline effects.

### Subpixel Shaders
`-rgb` and `-bgr` versions are for horizontal subpixel layouts, and `-vrgb` and `-vbgr` versions are for vertical subpixel layouts.
It supports subpixel rendering by offsetting positions of output pixels per each color.

Subpixel shaders need to sample input pixels three times per output pixel, and this could make them significantly slower than the basic shader.

### Gamma Corrected Preset
`sharp-shimmerless-gammacorrected.glslp` now uses the fast 2-pass linear-light pipeline in exact sRGB EOTF/OETF mode (`GAMMA_MODE = 1`, `GAMMA_OUT = 2`), replacing the slow 4-tap single-pass implementation.
