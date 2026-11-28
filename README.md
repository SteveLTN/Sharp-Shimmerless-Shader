# Sharp-Shimmerless-Shader-2

## A Sharp, Shimmering-free Shader for RetroArch
The Sharp-Shimmerless-2 shader guarantees the minimum number of interpolated pixels, i.e., the sharpest rectangular pixels possible, while inducing NO aliasing/shimmering.

## Acknowledgements

This repository is a fork of [zadpos/Sharp-Shimmerless-Shader](https://github.com/zadpos/Sharp-Shimmerless-Shader), renamed to **Sharp-Shimmerless-2** (`sharp-shimmerless-2-*`) so it can coexist alongside an existing upstream installation on RetroArch devices. Hats off to the original author and contributors for creating the box-filter approach that makes sharp, shimmering-free scaling possible.

## Improvements in This Fork

This fork builds on the original shader with additional correctness fixes, handheld compatibility work, and new quality/performance options:

- Fixed horizontal RGB/BGR subpixel sampling offsets.
- Improved box-filter overlap calculations by working in source coordinates.
- Fixed edge accuracy and out-of-range sampling on OpenGL ES devices with limited fragment-shader precision.
- Avoided FP16 overflow on devices without `highp` fragment support, reducing graphical artifacts on low-power handheld GPUs.
- Added an analytical zero-division filtering core shared by the GLSL and Slang implementations.
- Added a **1-pass 8-bit-FBO-safe linear-light preset** (`sharp-shimmerless-2-gamma-8bfbo-safe`) with adaptive 1/2/4-tap sampling and fast $\gamma = 2.0$ math—bringing gamma-corrected scaling to legacy `gl` / GLES drivers without needing a floating-point framebuffer and ~3–4× lighter than the original upstream gamma shader.
- Added **2-pass modern linear-light presets** (`sharp-shimmerless-2-gamma-modern` and `sharp-shimmerless-2-gamma-modern-hq`) with Box, $C^1$ Tent, and selectable Hann filtering, while preserving sharp integer-scaled axes.
- Added a single-pass single-tap fast sRGB preset (`sharp-shimmerless-2-non-gamma-fast`) for maximum speed.
- Added explicit detection of unsupported 8-bit framebuffer fallback in the 2-pass modern presets (displays solid magenta rather than silently producing crushed shadows).

## Compatibility and Performance Costs

Both **`shaders_glsl/`** and **`shaders_slang/`** ship the same **4 symmetrical presets** with identical names:

- **`sharp-shimmerless-2-gamma-modern`** and **`sharp-shimmerless-2-gamma-modern-hq`** use two passes with a filterable floating-point intermediate framebuffer (`RGBA16F`). Pass 0 linearizes once at `1× source` and Pass 1 performs a single hardware bilinear tap, making them scale best at 1080p–4K and in Exact sRGB / Tent / Hann modes on modern drivers (`vulkan`, `glcore`, `metal`, `d3d11/12`, or desktop `gl` with float FBOs).
- **`sharp-shimmerless-2-gamma-8bfbo-safe`** uses **one pass with no intermediate framebuffer**, avoiding RetroArch legacy `gl`'s 8-bit FBO fallback completely. It uses adaptive 1/2/4-tap nearest sampling (skipping gamma math entirely on interior pixels and doing only 2 taps on 1D edges) with fast $\gamma = 2.0$ (`c * c` / `sqrt`) by default.
- **`sharp-shimmerless-2-non-gamma-fast`** uses one pass and a single hardware bilinear tap with zero divisions and no gamma conversion—the fastest option, trading linear-light edge brightness for minimum GPU cost.

On older OpenGL ES devices using RetroArch's legacy **`gl`** driver where floating-point FBOs are unsupported, use **`shaders_glsl/sharp-shimmerless-2-gamma-8bfbo-safe.glslp`** for linear-light scaling (or **`shaders_glsl/sharp-shimmerless-2-non-gamma-fast.glslp`** for maximum speed). If a 2-pass `-gamma-modern` preset displays a solid magenta image, switch to `-gamma-8bfbo-safe` or switch RetroArch's video driver to `vulkan` / `glcore` with `shaders_slang/`.

## Set Up with an AI Agent

Paste this into your coding or deployment agent:

```text
Read https://github.com/SteveLTN/Sharp-Shimmerless-Shader-2/blob/main/RETROARCH-HANDHELD-AGENT-GUIDE.md and set up Sharp-Shimmerless-2 on my RetroArch device. Discover the device, operating system, RetroArch installation, video driver, and available control methods. Explain the shader presets and recommend the best option for my device. Start read-only, and get my approval before changing files, configuration, or video drivers.
```

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

Both **Slang** (`shaders_slang/`) and **GLSL** (`shaders_glsl/`) ship the exact same **four primary presets** with identical names:

### Which Preset Should I Use?

1. **Pick your folder by RetroArch video driver:**
   * **`shaders_slang/`** *(preferred on modern drivers)* — for **Vulkan, Metal, D3D11/12, or GLCore** (`glcore`).
   * **`shaders_glsl/`** — for RetroArch's legacy **`gl`** (OpenGL 2.1 / GLES 2.0–3.0) driver on Linux handhelds.
2. **Pick your preset by driver capability, screen, and performance:**

| Preset Name (`.slangp` / `.glslp`) | Passes | Float FBO? | Recommended For |
| :--- | :---: | :---: | :--- |
| **`sharp-shimmerless-2-gamma-modern`** | 2 | Yes (`RGBA16F`) | **Modern drivers** (`vulkan`, `glcore`, `metal`, `d3d11/12`, desktop `gl`) on 640×480 handhelds & general displays. Linear-light exact box filter with a single hardware bilinear tap in Pass 1. |
| **`sharp-shimmerless-2-gamma-8bfbo-safe`** | 1 | **No** | **Legacy `gl` / GLES drivers without float FBOs** (and any driver wanting zero FBO overhead). Adaptive 1/2/4-tap linear-light scaling with fast $\gamma = 2.0$ (`c * c` / `sqrt`)—immune to 8-bit FBO shadow crushing. |
| **`sharp-shimmerless-2-non-gamma-fast`** | 1 | **No** | **Maximum speed / battery** on ultra-low-power GPUs. Zero-division 1-tap sRGB box filter (trades linear-light edge brightness for minimum GPU cost). |
| **`sharp-shimmerless-2-gamma-modern-hq`** | 2 | Yes (`RGBA16F`) | **High-PPI displays** *(1024×768 TrimUI Brick / Pro, 720p, 1080p, 4K)* on modern drivers. Linear-light $C^1$ Tent filter (Hann selectable) for ultra-smooth scrolling; auto-snaps exact integer axes (e.g., 256 px → 1024 px = 4×) and scales $< 2\times$ back to sharp Box. |

> **Seeing a solid magenta screen?**
> Your RetroArch `gl` driver silently fell back from `float_framebuffer0 = true` to an 8-bit `RGBA8` intermediate (which would otherwise crush dark shadows `0–11/255` to pure black). The 2-pass `-gamma-modern` presets detect this via an alpha canary and show solid magenta on purpose — load **`shaders_glsl/sharp-shimmerless-2-gamma-8bfbo-safe.glslp`** (for linear-light scaling without float FBOs), or switch RetroArch's video driver to **`glcore`** / **`vulkan`** and use `shaders_slang/`.

### Tunable Shader Parameters (RetroArch Menu)

Under **Quick Menu → Shaders → Shader Parameters**:

* **`sharp-shimmerless-2-gamma-8bfbo-safe`**:
  * **`GAMMA_MODE`** — `0` = Off (sRGB), `1` = Fast $\gamma = 2.0$ (default), `2` = Exact piecewise sRGB.
  * **`FILTER_MODE`** — `0` = Box (default), `1` = Tent ($C^1$), `2` = Raised-Cosine / Hann.
  * **`SNAP_INT_AXES`** — `1` (default) keeps exact integer axes razor-sharp in Box mode even when Tent/Hann is selected.
* **`sharp-shimmerless-2-gamma-modern` & `sharp-shimmerless-2-gamma-modern-hq`**:
  * **`GAMMA_MODE` / `GAMMA_OUT`** — Default is fast $\gamma = 2.0$ (`GAMMA_MODE = 0`, `GAMMA_OUT = 1`). Set `GAMMA_MODE = 1` and `GAMMA_OUT = 2` for exact piecewise sRGB EOTF/OETF.
  * **`FILTER_MODE`** — `0` = Box (default on `-gamma-modern`), `1` = Tent (default on `-gamma-modern-hq`), `2` = Hann.
  * **`SNAP_INT_AXES`** — `1` (default) snaps exact integer axes back to sharp Box.

### Color Correction (GBA / GBC)
Core-side color correction (mGBA, Gambatte, SameBoy) outputs standard sRGB prior to shader execution and works seamlessly with all presets. If using shader-side color correction (`gba-color` / `gbc-color`), prepend it at `1x source` *before* `sharp-shimmerless-2-linearize` (or before `sharp-shimmerless-2-8bfbo-safe`) rather than after scaling.

### Extra GLSL Variants (`shaders_glsl/extras/`)

Additional GLSL-only effect variants are kept in **`shaders_glsl/extras/`** (each prefixed with `sharp-shimmerless-2-`):

* **Curvature Shaders** (`-curvature`, `-curvature-grid`, `-curvature-scanlines`): Applies CRT-like curvature, optionally combined with grid or scanlines.
* **Grid / Scanlines Shaders** (`-grid`, `-scanlines`): Applies LCD grid or scanline overlays.
* **Subpixel Shaders** (`-subpixel-rgb`, `-subpixel-bgr`, `-subpixel-vrgb`, `-subpixel-vbgr`): Supports horizontal (`rgb`/`bgr`) and vertical (`vrgb`/`vbgr`) subpixel layouts by offsetting output pixel positions per color channel (samples input 3× per pixel, slower than the base shaders).
