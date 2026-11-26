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

Both **Slang** (`shaders_slang/`) and **GLSL** (`shaders_glsl/`) ship the same **three primary presets** powered by a shared zero-division analytical core:

### Which Preset Should I Use?

1. **Pick your folder by RetroArch video driver:**
   * **`shaders_slang/`** *(preferred)* — for **Vulkan, Metal, D3D11/12, or GLCore** (`glcore`). Filterable half-float FBOs are guaranteed.
   * **`shaders_glsl/`** — for RetroArch's legacy **`gl`** (OpenGL 2.1 / GLES 2.0–3.0) driver on Linux handhelds.
2. **Pick your preset by screen & device:**

| Your Screen / Setup | Recommended Preset | Passes | Why |
| :--- | :--- | :---: | :--- |
| **640×480 handhelds** *(RG35XX, Miyoo Mini+, R36S)* & **general displays** | **`sharp-shimmerless`** *(default — try this first)* | 2 | Linear-light exact box filter: sharpest rectangular pixels with zero geometric or brightness shimmering. |
| **High-PPI displays** *(1024×768 TrimUI Brick / Pro, 720p, 1080p, 4K)* | **`sharp-shimmerless-smooth-hq`** | 2 | Linear-light $C^1$ band-limited Tent filter (Hann selectable) for ultra-smooth scrolling; auto-snaps exact integer axes (e.g., 256 px → 1024 px = 4×) and scales $< 2\times$ back to sharp Box. |
| **Legacy `gl` drivers without float FBOs** *(or max battery/speed)* | **`sharp-shimmerless-fast-fallback`** | 1 | Zero-division 1-pass sRGB box filter. Works on every GL/GLES 2.0 device without needing a float FBO (trades linear-light edge brightness for maximum compatibility). |

> **Seeing a solid magenta screen?**
> Your RetroArch `gl` driver silently fell back from `float_framebuffer` to an 8-bit `RGBA8` intermediate (which would otherwise crush dark shadows `0–11/255` to pure black). The 2-pass presets detect this via an alpha canary and show solid magenta on purpose — either switch RetroArch's video driver to **`glcore`** or **`vulkan`** (and use `shaders_slang/`), or load **`shaders_glsl/sharp-shimmerless-fast-fallback.glslp`**.

*(For existing saved configs, `shaders_glsl/sharp-shimmerless-gammacorrected.glslp` is kept as a compatibility preset pointing to the 2-pass exact-sRGB pipeline.)*

### Tunable Shader Parameters (RetroArch Menu)

All three presets share the same core and can be fine-tuned live under **Quick Menu → Shaders → Shader Parameters**:

* **`GAMMA_MODE` / `GAMMA_OUT`** — Default is fast $\gamma = 2.0$ (`c * c` / `sqrt`, ~95% of exact sRGB at minimal GPU cost). Set `GAMMA_MODE = 1` and `GAMMA_OUT = 2` for exact piecewise sRGB EOTF/OETF.
* **`FILTER_MODE`** — `0` = Box (sharpest), `1` = Tent ($C^1$, -26 dB sidelobes, default on `-smooth-hq`), `2` = Raised-Cosine / Hann (-31.5 dB sidelobes).
* **`SNAP_INT_AXES`** — `1` (default) keeps exact integer axes (like 4× horizontal on NES/SNES at 1024×768) razor-sharp in Box mode even when using `-smooth-hq`.

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
