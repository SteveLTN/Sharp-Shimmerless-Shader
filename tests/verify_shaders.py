#!/usr/bin/env python3
"""GPU-rendered verification suite for Sharp-Shimmerless-2 GLSL & Slang shaders.

Runs real offscreen OpenGL 2.1 (GLSL 120) renders on macOS via ctypes + OpenGL.framework,
testing 1-pass (sRGB and 8-bit-FBO-safe linear-light) and 2-pass (GL_RGBA16F) pipelines
without third-party dependencies.
"""

from __future__ import annotations

import ctypes as c
from fractions import Fraction
from math import ceil, floor, pi, sin
from pathlib import Path
import re
from struct import pack, unpack
import sys

ROOT = Path(__file__).resolve().parent.parent

# OpenGL constants
GL_TEXTURE_2D = 0x0DE1
GL_RGBA = 0x1908
GL_RGBA8 = 0x8058
GL_RGBA16F = 0x881A
GL_UNSIGNED_BYTE = 0x1401
GL_FLOAT = 0x1406
GL_LINEAR = 0x2601
GL_NEAREST = 0x2600
GL_CLAMP_TO_EDGE = 0x812F
GL_TEXTURE_MIN_FILTER = 0x2801
GL_TEXTURE_MAG_FILTER = 0x2800
GL_TEXTURE_WRAP_S = 0x2802
GL_TEXTURE_WRAP_T = 0x2803
GL_VERTEX_SHADER = 0x8B31
GL_FRAGMENT_SHADER = 0x8B30
GL_COMPILE_STATUS = 0x8B81
GL_LINK_STATUS = 0x8B82
GL_FRAMEBUFFER_EXT = 0x8D40
GL_COLOR_ATTACHMENT0_EXT = 0x8CE0
GL_FRAMEBUFFER_COMPLETE_EXT = 0x8CD5
GL_DITHER = 0x0BD0
GL_TRIANGLE_STRIP = 5
GL_VERSION = 0x1F02

U, I, V, S, F, B = c.c_uint, c.c_int, c.c_void_p, c.c_char_p, c.c_float, c.c_ubyte
P = c.POINTER

EXTRA_GLSL_VARIANTS = [
    "curvature",
    "curvature-grid",
    "curvature-scanlines",
    "grid",
    "scanlines",
    "subpixel-bgr",
    "subpixel-rgb",
    "subpixel-vbgr",
    "subpixel-vrgb",
]


class GLContext:
    def __init__(self) -> None:
        self.gl = c.CDLL("/System/Library/Frameworks/OpenGL.framework/OpenGL")
        fmt, ctx, count = V(), V(), I()
        assert (
            self._call("CGLChoosePixelFormat", I, (P(I), P(V), P(I)), (I * 1)(0), c.byref(fmt), c.byref(count)) == 0
            and fmt.value
        )
        assert self._call("CGLCreateContext", I, (V, V, P(V)), fmt, None, c.byref(ctx)) == 0
        assert self._call("CGLSetCurrentContext", I, (V,), ctx) == 0
        self.version = self._call("glGetString", S, (U,), GL_VERSION).decode()
        self._gl("Disable", (U,), GL_DITHER)

    def _call(self, name: str, ret, args, *values):
        fn = getattr(self.gl, name)
        fn.restype, fn.argtypes = ret, args
        return fn(*values)

    def _gl(self, name: str, args, *values):
        return self._call("gl" + name, None, args, *values)

    def _check(self, kind: str, obj: int, status: int) -> None:
        ok = I()
        self._gl(f"Get{kind}iv", (U, U, P(I)), obj, status, c.byref(ok))
        if not ok.value:
            log = c.create_string_buffer(8192)
            self._gl(f"Get{kind}InfoLog", (U, I, P(I), V), obj, len(log), None, log)
            raise RuntimeError(f"GL {kind} error:\n{log.value.decode()}")

    def compile_program(self, source: str, defines: list[str] | None = None, version: str = "120") -> int:
        extra = "".join(f"#define {d}\n" for d in (defines or []))
        program = self._call("glCreateProgram", U, ())
        shaders = []
        for stage, stype in [("VERTEX", GL_VERTEX_SHADER), ("FRAGMENT", GL_FRAGMENT_SHADER)]:
            sh = self._call("glCreateShader", U, (U,), stype)
            code = f"#version {version}\n#define {stage}\n{extra}{source}".encode()
            ptr = S(code)
            self._gl("ShaderSource", (U, I, P(S), P(I)), sh, 1, c.byref(ptr), None)
            self._gl("CompileShader", (U,), sh)
            self._check("Shader", sh, GL_COMPILE_STATUS)
            self._gl("AttachShader", (U, U), program, sh)
            shaders.append(sh)
        self._gl("LinkProgram", (U,), program)
        self._check("Program", program, GL_LINK_STATUS)
        for sh in shaders:
            self._gl("DeleteShader", (U,), sh)
        return program

    def create_texture(
        self,
        width: int,
        height: int,
        data: bytes | None,
        *,
        linear: bool = True,
        internal_format: int = GL_RGBA8,
        pixel_type: int = GL_UNSIGNED_BYTE,
    ) -> int:
        tex = U()
        self._gl("GenTextures", (I, P(U)), 1, c.byref(tex))
        self._gl("BindTexture", (U, U), GL_TEXTURE_2D, tex)
        filt = GL_LINEAR if linear else GL_NEAREST
        for param, val in [
            (GL_TEXTURE_MIN_FILTER, filt),
            (GL_TEXTURE_MAG_FILTER, filt),
            (GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE),
            (GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE),
        ]:
            self._gl("TexParameteri", (U, U, I), GL_TEXTURE_2D, param, val)
        self._gl(
            "TexImage2D",
            (U, I, I, I, I, I, U, U, V),
            GL_TEXTURE_2D,
            0,
            internal_format,
            width,
            height,
            0,
            GL_RGBA,
            pixel_type,
            data,
        )
        return tex.value

    def create_fbo(self, tex: int) -> int:
        fbo = U()
        self._gl("GenFramebuffersEXT", (I, P(U)), 1, c.byref(fbo))
        self._gl("BindFramebufferEXT", (U, U), GL_FRAMEBUFFER_EXT, fbo)
        self._gl("FramebufferTexture2DEXT", (U, U, U, U, I), GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_2D, tex, 0)
        status = self._call("glCheckFramebufferStatusEXT", U, (U,), GL_FRAMEBUFFER_EXT)
        assert status == GL_FRAMEBUFFER_COMPLETE_EXT, f"Incomplete FBO: 0x{status:X}"
        return fbo.value

    def draw_pass(
        self,
        program: int,
        in_tex: int,
        out_fbo: int,
        in_size: tuple[int, int],
        tex_size: tuple[int, int],
        out_size: tuple[int, int],
        params: dict[str, float] | None = None,
    ) -> None:
        w_in, h_in = in_size
        w_tex, h_tex = tex_size
        w_out, h_out = out_size
        self._gl("BindFramebufferEXT", (U, U), GL_FRAMEBUFFER_EXT, out_fbo)
        self._gl("Viewport", (I, I, I, I), 0, 0, w_out, h_out)
        self._gl("UseProgram", (U,), program)
        self._gl("BindTexture", (U, U), GL_TEXTURE_2D, in_tex)

        def uloc(name: str) -> int:
            return self._call("glGetUniformLocation", I, (U, S), program, name.encode())

        for name, (vx, vy) in [("TextureSize", tex_size), ("InputSize", in_size), ("OutputSize", out_size)]:
            loc = uloc(name)
            if loc >= 0:
                self._gl("Uniform2f", (I, F, F), loc, float(vx), float(vy))
        for name, val in (params or {}).items():
            loc = uloc(name)
            if loc >= 0:
                self._gl("Uniform1f", (I, F), loc, float(val))
        loc_tex = uloc("Texture")
        if loc_tex >= 0:
            self._gl("Uniform1i", (I, I), loc_tex, 0)
        loc_mvp = uloc("MVPMatrix")
        if loc_mvp >= 0:
            ident = (F * 16)(*(1.0 if i % 5 == 0 else 0.0 for i in range(16)))
            self._gl("UniformMatrix4fv", (I, I, B, P(F)), loc_mvp, 1, 0, ident)

        arrays = []
        quads = [
            ("VertexCoord", [-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0]),
            ("TexCoord", [0.0, 0.0, w_in / w_tex, 0.0, 0.0, h_in / h_tex, w_in / w_tex, h_in / h_tex]),
        ]
        for name, coords in quads:
            loc = self._call("glGetAttribLocation", I, (U, S), program, name.encode())
            if loc >= 0:
                arr = (F * 8)(*coords)
                arrays.append(arr)
                self._gl("VertexAttribPointer", (U, I, U, B, I, V), loc, 2, GL_FLOAT, 0, 0, arr)
                self._gl("EnableVertexAttribArray", (U,), loc)
        self._gl("DrawArrays", (U, I, I), GL_TRIANGLE_STRIP, 0, 4)
        err = self._call("glGetError", U, ())
        assert err == 0, f"GL error 0x{err:X}"

    def read_rgba8(self, width: int, height: int) -> bytes:
        buf = (B * (4 * width * height))()
        self._gl("ReadPixels", (I, I, I, I, U, U, V), 0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, buf)
        err = self._call("glGetError", U, ())
        assert err == 0, f"GL read error 0x{err:X}"
        return bytes(buf)

    def render_1pass(
        self,
        shader_src: str,
        in_rgba: bytes,
        in_size: tuple[int, int],
        tex_size: tuple[int, int],
        out_size: tuple[int, int],
        params: dict[str, float] | None = None,
        defines: list[str] | None = None,
        linear_input: bool = True,
    ) -> bytes:
        prog = self.compile_program(shader_src, defines=defines)
        in_tex = self.create_texture(tex_size[0], tex_size[1], in_rgba, linear=linear_input)
        out_tex = self.create_texture(out_size[0], out_size[1], None, linear=False)
        fbo = self.create_fbo(out_tex)
        try:
            self.draw_pass(prog, in_tex, fbo, in_size, tex_size, out_size, params=params)
            return self.read_rgba8(out_size[0], out_size[1])
        finally:
            for tid in (in_tex, out_tex):
                self._gl("DeleteTextures", (I, P(U)), 1, c.byref(U(tid)))
            self._gl("DeleteFramebuffersEXT", (I, P(U)), 1, c.byref(U(fbo)))
            self._gl("DeleteProgram", (U,), prog)

    def render_2pass(
        self,
        pass0_src: str,
        pass1_src: str,
        in_rgba: bytes,
        in_size: tuple[int, int],
        tex_size: tuple[int, int],
        out_size: tuple[int, int],
        *,
        fbo0_tex_size: tuple[int, int] | None = None,
        fbo0_float: bool = True,
        pass0_params: dict[str, float] | None = None,
        pass1_params: dict[str, float] | None = None,
    ) -> bytes:
        fbo0_tex_size = fbo0_tex_size or in_size
        p0 = self.compile_program(pass0_src, defines=["PARAMETER_UNIFORM"])
        p1 = self.compile_program(pass1_src, defines=["PARAMETER_UNIFORM"])
        in_tex = self.create_texture(tex_size[0], tex_size[1], in_rgba, linear=False)
        # Pre-fill mid FBO with bright magenta padding when padded so any border bleed is caught.
        pad_data = None
        if fbo0_tex_size != in_size:
            if fbo0_float:
                pad_vals = (F * (4 * fbo0_tex_size[0] * fbo0_tex_size[1]))()
                for idx in range(0, len(pad_vals), 4):
                    pad_vals[idx] = 1.0
                    pad_vals[idx + 1] = 0.0
                    pad_vals[idx + 2] = 1.0
                    pad_vals[idx + 3] = 2.0
                pad_data = bytes(pad_vals)
            else:
                pad_data = bytes((255, 0, 255, 255)) * (fbo0_tex_size[0] * fbo0_tex_size[1])
        mid_tex = self.create_texture(
            fbo0_tex_size[0],
            fbo0_tex_size[1],
            pad_data,
            linear=True,
            internal_format=GL_RGBA16F if fbo0_float else GL_RGBA8,
            pixel_type=GL_FLOAT if fbo0_float else GL_UNSIGNED_BYTE,
        )
        fbo0 = self.create_fbo(mid_tex)
        out_tex = self.create_texture(out_size[0], out_size[1], None, linear=False)
        fbo1 = self.create_fbo(out_tex)
        try:
            self.draw_pass(p0, in_tex, fbo0, in_size, tex_size, in_size, params=pass0_params)
            self.draw_pass(p1, mid_tex, fbo1, in_size, fbo0_tex_size, out_size, params=pass1_params)
            return self.read_rgba8(out_size[0], out_size[1])
        finally:
            for tid in (in_tex, mid_tex, out_tex):
                self._gl("DeleteTextures", (I, P(U)), 1, c.byref(U(tid)))
            for fid in (fbo0, fbo1):
                self._gl("DeleteFramebuffersEXT", (I, P(U)), 1, c.byref(U(fid)))
            self._gl("DeleteProgram", (U,), p0)
            self._gl("DeleteProgram", (U,), p1)


def srgb_to_linear(v: float) -> float:
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def linear_to_srgb(v: float) -> float:
    v = max(v, 0.0)
    return v * 12.92 if v <= 0.0031308 else 1.055 * (v ** (1.0 / 2.4)) - 0.055


def exact_linear_reference_2d(
    in_rgba: bytes, w_in: int, h_in: int, w_tex: int, w_out: int, h_out: int, filter_mode: float, gamma_mode: float
) -> list[tuple[float, float, float]]:
    def axis_1d(n: int, m: int):
        raw_scale = m / n
        scale = max(raw_scale, 1.0)
        use_smooth = (raw_scale >= 1.999) and (abs(raw_scale - floor(raw_scale + 0.5)) > 0.001)
        res = []
        for k in range(m):
            texel = (k + 0.5) * (n / m)
            b = floor(texel + 0.5)
            d = (texel - b) * scale
            w = min(1.0, max(0.0, d + 0.5))
            if filter_mode > 0.5 and use_smooth:
                ds = min(1.0, max(-1.0, d))
                if filter_mode < 1.5:
                    w = 0.5 + ds - 0.5 * ds * abs(ds)
                else:
                    w = 0.0 if abs(d) >= 1.0 and d < 0 else (1.0 if abs(d) >= 1.0 else 0.5 * (1.0 + ds + sin(pi * ds) / pi))
            res.append((min(n - 1, max(0, b - 1)), min(n - 1, max(0, b)), w))
        return res

    to_lin = (lambda v: v * v) if gamma_mode < 1.5 else srgb_to_linear
    from_lin = (lambda v: max(v, 0.0) ** 0.5) if gamma_mode < 1.5 else linear_to_srgb
    lin_lut = [to_lin(i / 255.0) for i in range(256)]
    ax_x = axis_1d(w_in, w_out)
    ax_y = axis_1d(h_in, h_out)
    out = []
    for iy0, iy1, wy in ax_y:
        for ix0, ix1, wx in ax_x:
            o00 = 4 * (iy0 * w_tex + ix0)
            o10 = 4 * (iy0 * w_tex + ix1)
            o01 = 4 * (iy1 * w_tex + ix0)
            o11 = 4 * (iy1 * w_tex + ix1)
            rgb = []
            for ch in range(3):
                c0 = lin_lut[in_rgba[o00 + ch]] * (1.0 - wx) + lin_lut[in_rgba[o10 + ch]] * wx
                c1 = lin_lut[in_rgba[o01 + ch]] * (1.0 - wx) + lin_lut[in_rgba[o11 + ch]] * wx
                rgb.append(from_lin(c0 * (1.0 - wy) + c1 * wy) * 255.0)
            out.append((rgb[0], rgb[1], rgb[2]))
    return out


def float16_round(x: float) -> float:
    return unpack("e", pack("e", x))[0]


def make_pattern_rgba(w_in: int, h_in: int, w_tex: int, h_tex: int, pad_rgb=(255, 0, 255)) -> bytes:
    buf = bytearray(4 * w_tex * h_tex)
    for y in range(h_tex):
        for x in range(w_tex):
            off = 4 * (y * w_tex + x)
            if x < w_in and y < h_in:
                r = 255 if ((x + y) % 2 == 0) else 0
                g = 255 if (x % 3 == 0) else 40
                b = (x * 13 + y * 29) % 256
                buf[off : off + 4] = bytes((r, g, b, 255))
            else:
                buf[off : off + 4] = bytes((*pad_rgb, 255))
    return bytes(buf)


def exact_box_reference_2d(in_rgba: bytes, w_in: int, h_in: int, w_tex: int, w_out: int, h_out: int) -> list[tuple[float, float, float]]:
    def weights_1d(n: int, m: int):
        res = []
        for k in range(m):
            a, b = Fraction(k * n, m), Fraction((k + 1) * n, m)
            span = b - a
            terms = []
            for i in range(floor(a), ceil(b)):
                ov = min(b, i + 1) - max(a, i)
                if ov > 0:
                    terms.append((min(max(i, 0), n - 1), float(ov / span)))
            res.append(terms)
        return res

    wx = weights_1d(w_in, w_out)
    wy = weights_1d(h_in, h_out)
    out = []
    for y in range(h_out):
        for x in range(w_out):
            r = g = b = 0.0
            for iy, fy in wy[y]:
                for ix, fx in wx[x]:
                    w = fx * fy
                    off = 4 * (iy * w_tex + ix)
                    r += in_rgba[off] * w
                    g += in_rgba[off + 1] * w
                    b += in_rgba[off + 2] * w
            out.append((r, g, b))
    return out


def parse_preset(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise AssertionError(f"Malformed line in {path}: {raw}")
        k, v = [part.strip() for part in line.split("=", 1)]
        data[k] = v.strip('"')
    return data


def max_rgb_diff(a: bytes, b: bytes) -> int:
    assert len(a) == len(b)
    return max(
        max(abs(a[i] - b[i]), abs(a[i + 1] - b[i + 1]), abs(a[i + 2] - b[i + 2]))
        for i in range(0, len(a), 4)
    )


def test_presets_and_structure() -> None:
    preset_specs = [
        ("sharp-shimmerless-2-gamma-modern", 2, None),
        ("sharp-shimmerless-2-gamma-8bfbo-safe", 1, "false"),
        ("sharp-shimmerless-2-non-gamma-fast", 1, "true"),
        ("sharp-shimmerless-2-gamma-modern-hq", 2, None),
    ]
    expected_stems = {stem for stem, _, _ in preset_specs}

    for folder, ext in [("shaders_glsl", "glslp"), ("shaders_slang", "slangp")]:
        top_presets = {p.stem for p in (ROOT / folder).glob(f"*.{ext}")}
        assert top_presets == expected_stems, f"{folder}: expected top-level presets {sorted(expected_stems)}, got {sorted(top_presets)}"

        for stem, expected_passes, expected_filter0 in preset_specs:
            rel = f"{folder}/{stem}.{ext}"
            p = ROOT / rel
            cfg = parse_preset(p)
            n = int(cfg["shaders"])
            assert n == expected_passes, f"{rel}: expected {expected_passes} pass(es), got {n}"
            declared_params: set[str] = set()
            for i in range(n):
                sp = (p.parent / cfg[f"shader{i}"]).resolve()
                assert sp.exists(), f"{rel} references missing shader{i}: {cfg[f'shader{i}']}"
                declared_params.update(re.findall(r"#pragma\s+parameter\s+(\w+)", sp.read_text()))
            if "parameters" in cfg and cfg["parameters"]:
                for pname in cfg["parameters"].split(";"):
                    pname = pname.strip()
                    assert pname in declared_params, f"{rel} sets undeclared parameter {pname}"
                    assert pname in cfg, f"{rel} lists {pname} in parameters without a value"
            if n == 2:
                assert cfg.get("scale_type0") == "source", f"{rel}: pass 0 must use scale_type0 = source"
                assert float(cfg.get("scale0", "0")) == 1.0, f"{rel}: pass 0 must use scale0 = 1.0"
                assert cfg.get("float_framebuffer0") == "true", f"{rel}: pass 0 must enable float_framebuffer0"
                assert cfg.get("filter_linear1") == "true", f"{rel}: pass 1 must enable filter_linear1"
            else:
                assert "float_framebuffer0" not in cfg, f"{rel}: 1-pass preset must not request float_framebuffer0"
                assert cfg.get("filter_linear0") == expected_filter0, f"{rel}: expected filter_linear0 = {expected_filter0}"

    expected_shader_stems = {
        "sharp-shimmerless-2-linearize",
        "sharp-shimmerless-2-core",
        "sharp-shimmerless-2-8bfbo-safe",
        "sharp-shimmerless-2-fast",
    }
    for folder, ext in [("shaders_glsl/shaders", "glsl"), ("shaders_slang/shaders", "slang")]:
        actual = {p.stem for p in (ROOT / folder).glob(f"*.{ext}")}
        assert actual == expected_shader_stems, f"{folder}: expected {sorted(expected_shader_stems)}, got {sorted(actual)}"

    # Verify all 9 extra GLSL variants live cleanly under shaders_glsl/extras/
    extras_dir = ROOT / "shaders_glsl/extras"
    actual_extras = {p.stem for p in extras_dir.glob("*.glslp")}
    expected_extras = {f"sharp-shimmerless-2-{v}" for v in EXTRA_GLSL_VARIANTS}
    assert actual_extras == expected_extras, f"extras mismatch: {sorted(actual_extras)}"
    for stem in sorted(expected_extras):
        p = extras_dir / f"{stem}.glslp"
        cfg = parse_preset(p)
        sp = (p.parent / cfg["shader0"]).resolve()
        assert sp.exists(), f"{p} references missing shader0: {cfg['shader0']}"

    # GLES defaults unqualified sampler2D to lowp; verify explicit SIZE_PRECISION on all core GLSL shaders.
    for stem in sorted(expected_shader_stems):
        rel = f"shaders_glsl/shaders/{stem}.glsl"
        src = (ROOT / rel).read_text()
        assert "uniform SIZE_PRECISION sampler2D Texture;" in src, f"{rel}: sampler2D must declare SIZE_PRECISION"

    # GLSL ES 3.00 requires fragment precision declaration before `out vec4 FragColor;`.
    safe_frag = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-8bfbo-safe.glsl").read_text().split("#elif defined(FRAGMENT)", 1)[1]
    assert safe_frag.index("precision highp float;") < safe_frag.index("out vec4 FragColor;"), (
        "8bfbo-safe fragment precision must precede out vec4 FragColor for GLSL ES 3.00"
    )

    print("[PASS] Symmetrical 4-preset structure (GLSL + Slang), extras layout, GLES sampler precision, and parameters")


def test_box_equivalence_and_padding(gl: GLContext) -> None:
    core_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-core.glsl").read_text()
    fast_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-fast.glsl").read_text()
    safe_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-8bfbo-safe.glsl").read_text()

    cases = [
        ((240, 160), (256, 256), (640, 427)),
        ((240, 160), (256, 256), (640, 480)),
        ((256, 240), (256, 256), (640, 480)),
        ((256, 240), (256, 256), (1024, 768)),
        ((320, 240), (512, 256), (1024, 768)),
        ((240, 160), (256, 256), (1024, 683)),
        ((240, 160), (256, 256), (1278, 852)),
        ((240, 160), (256, 256), (1272, 720)),
    ]
    for in_sz, tex_sz, out_sz in cases:
        in_rgba = make_pattern_rgba(in_sz[0], in_sz[1], tex_sz[0], tex_sz[1], pad_rgb=(255, 0, 255))
        ref = exact_box_reference_2d(in_rgba, in_sz[0], in_sz[1], tex_sz[0], out_sz[0], out_sz[1])
        for label, src, params, linear_in in [
            ("core(srgb)", core_src, {"FILTER_MODE": 0.0, "GAMMA_OUT": 0.0}, True),
            ("fast", fast_src, {}, True),
            ("8bfbo-safe(srgb)", safe_src, {"FILTER_MODE": 0.0, "GAMMA_MODE": 0.0}, False),
        ]:
            got = gl.render_1pass(
                src, in_rgba, in_sz, tex_sz, out_sz, params=params, defines=["PARAMETER_UNIFORM"], linear_input=linear_in
            )
            max_err = 0.0
            for idx, (rr, rg, rb) in enumerate(ref):
                off = 4 * idx
                err = max(abs(got[off] - rr), abs(got[off + 1] - rg), abs(got[off + 2] - rb))
                if err > max_err:
                    max_err = err
            assert max_err <= 1.5, f"{label} {in_sz}->{out_sz} (tex {tex_sz}): max_err={max_err:.2f}/255"
    print(f"[PASS] Exact 2D box equivalence + padded-atlas safety across {len(cases)} resolutions (fast, core, 8bfbo-safe)")


def test_8bfbo_safe_linear_parity_and_shadows(gl: GLContext) -> None:
    lin_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-linearize.glsl").read_text()
    core_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-core.glsl").read_text()
    safe_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-8bfbo-safe.glsl").read_text()

    # Covers 1-tap interior, 2-tap horizontal edge (256x240->640x480), 2-tap vertical edge
    # (256x240->1024x768), and 4-tap 2D corners + padded atlas (240x160->640x427).
    res_cases = [
        ((256, 240), (256, 256), (640, 480)),
        ((256, 240), (256, 256), (1024, 768)),
        ((240, 160), (256, 256), (640, 427)),
    ]
    mode_cases = [
        ("box+gamma2", 0.0, 1.0, 0.0, 1.0),
        ("box+srgb", 0.0, 2.0, 1.0, 2.0),
        ("tent+gamma2", 1.0, 1.0, 0.0, 1.0),
        ("hann+srgb", 2.0, 2.0, 1.0, 2.0),
    ]
    # First check 1-pass 8bfbo-safe directly against exact FP64 analytical math (<= 1.0/255)
    # across 1-tap interior, 2-tap H/V edges, and 4-tap 2D corners with padded atlas.
    exact_cases = [
        ((64, 48), (64, 64), (160, 96)),
        ((64, 48), (64, 64), (256, 154)),
        ((60, 40), (64, 64), (160, 107)),
    ]
    for in_sz, tex_sz, out_sz in exact_cases:
        in_rgba = make_pattern_rgba(in_sz[0], in_sz[1], tex_sz[0], tex_sz[1], pad_rgb=(255, 0, 255))
        for label, fmode, safe_gm, _, _ in mode_cases:
            got_1p = gl.render_1pass(
                safe_src,
                in_rgba,
                in_sz,
                tex_sz,
                out_sz,
                params={"FILTER_MODE": fmode, "GAMMA_MODE": safe_gm, "SNAP_INT_AXES": 1.0},
                defines=["PARAMETER_UNIFORM"],
                linear_input=False,
            )
            ref = exact_linear_reference_2d(in_rgba, in_sz[0], in_sz[1], tex_sz[0], out_sz[0], out_sz[1], fmode, safe_gm)
            max_err = max(
                max(abs(got_1p[4 * i] - r), abs(got_1p[4 * i + 1] - g), abs(got_1p[4 * i + 2] - b))
                for i, (r, g, b) in enumerate(ref)
            )
            assert max_err <= 1.0, f"8bfbo-safe vs exact math {label} {in_sz}->{out_sz}: max_err={max_err:.2f}/255"

    # Also verify full-resolution parity against 2-pass RGBA16F (<= 2/255 allows for GPU hardware
    # 8-bit fixed-point bilinear weight quantization near black under sqrt() in 2-pass GL_LINEAR).
    for in_sz, tex_sz, out_sz in res_cases:
        in_rgba = make_pattern_rgba(in_sz[0], in_sz[1], tex_sz[0], tex_sz[1], pad_rgb=(255, 0, 255))
        for label, fmode, safe_gm, p0_gm, p1_go in mode_cases:
            got_1p = gl.render_1pass(
                safe_src,
                in_rgba,
                in_sz,
                tex_sz,
                out_sz,
                params={"FILTER_MODE": fmode, "GAMMA_MODE": safe_gm, "SNAP_INT_AXES": 1.0},
                defines=["PARAMETER_UNIFORM"],
                linear_input=False,
            )
            got_2p = gl.render_2pass(
                lin_src,
                core_src,
                in_rgba,
                in_sz,
                tex_sz,
                out_sz,
                fbo0_tex_size=tex_sz,
                fbo0_float=True,
                pass0_params={"GAMMA_MODE": p0_gm},
                pass1_params={"FILTER_MODE": fmode, "GAMMA_OUT": p1_go, "SNAP_INT_AXES": 1.0},
            )
            # Compare in linear light: hardware GL_LINEAR quantizes sub-texel weights to 8-bit
            # fixed point (0.5/256 ~= 0.002 linear), which sqrt'(0) amplifies to ~11/255 in sRGB
            # even though linear-light brightness differs by < 0.5%.
            to_lin = (lambda u: (u / 255.0) ** 2) if safe_gm < 1.5 else (lambda u: srgb_to_linear(u / 255.0))
            max_lin_diff = max(
                max(
                    abs(to_lin(got_1p[i]) - to_lin(got_2p[i])),
                    abs(to_lin(got_1p[i + 1]) - to_lin(got_2p[i + 1])),
                    abs(to_lin(got_1p[i + 2]) - to_lin(got_2p[i + 2])),
                )
                for i in range(0, len(got_1p), 4)
            )
            assert max_lin_diff <= 0.01, f"8bfbo-safe vs 2-pass {label} {in_sz}->{out_sz}: max_lin_diff={max_lin_diff:.4f}"

    # Dark shadow preservation: values 0..24/255 (which crush to 0 on an 8-bit linear FBO)
    # must survive intact with zero crushing at 3x integer scale and fractional scale.
    w_in, h_in = 32, 8
    dark_buf = bytearray(4 * w_in * h_in)
    for y in range(h_in):
        for x in range(w_in):
            v = x  # 0..31/255
            off = 4 * (y * w_in + x)
            dark_buf[off : off + 4] = bytes((v, v, v, 255))
    for gm in (1.0, 2.0):
        out = gl.render_1pass(
            safe_src,
            bytes(dark_buf),
            (w_in, h_in),
            (w_in, h_in),
            (w_in * 3, h_in * 3),
            params={"FILTER_MODE": 0.0, "GAMMA_MODE": gm, "SNAP_INT_AXES": 1.0},
            defines=["PARAMETER_UNIFORM"],
            linear_input=False,
        )
        for x in range(w_in):
            got_v = out[4 * (x * 3 + 1)]
            assert got_v == x, f"Dark shadow {x}/255 corrupted to {got_v}/255 (GAMMA_MODE={gm})"

    # Exact integer (3x, 5x) and half-integer (1.5x) scale purity: zero invscale rounding leakage
    # on pure black/white checkerboards (even under gamma 2.0 sqrt) and zero NaN under exact sRGB.
    for w_in, w_out, expect_exact_bw in [(240, 720, True), (240, 1200, True), (320, 480, False)]:
        bw = bytearray(4 * w_in * 4)
        for y in range(4):
            for x in range(w_in):
                v = 255 if ((x + y) % 2 == 0) else 0
                bw[4 * (y * w_in + x) : 4 * (y * w_in + x) + 4] = bytes((v, 0, v, 255))
        for gm in (1.0, 2.0):
            out = gl.render_1pass(
                safe_src, bytes(bw), (w_in, 4), (w_in, 4), (w_out, 4),
                params={"FILTER_MODE": 0.0, "GAMMA_MODE": gm, "SNAP_INT_AXES": 1.0},
                defines=["PARAMETER_UNIFORM"], linear_input=False,
            )
            if expect_exact_bw:
                vals = {out[4 * i] for i in range(w_out * 4)}
                assert vals == {0, 255}, f"8bfbo-safe {w_in}->{w_out} (GAMMA_MODE={gm}) leaked non-0/255 values: {sorted(vals)[:8]}"
            # Pure-zero green channel must stay exact 0 (never NaN -> non-zero) on every edge/interior pixel.
            assert all(out[4 * i + 1] == 0 for i in range(w_out * 4)), f"Zero channel corrupted at {w_in}->{w_out} (GAMMA_MODE={gm})"

    print("[PASS] 1-pass 8bfbo-safe matches exact FP64 math (<=1/255) & 2-pass RGBA16F (<=1% linear) + 3x/5x/shadow exact")


def test_fp16_drift_immunity(gl: GLContext) -> None:
    core_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-core.glsl").read_text()
    fast_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-fast.glsl").read_text()
    safe_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-8bfbo-safe.glsl").read_text()

    # Stress COMPAT_PRECISION (mediump) scale varying on core.glsl while invscale remains highp.
    for in_sz, out_sz in [((240, 160), (1278, 852)), ((240, 160), (1272, 720))]:
        in_rgba = make_pattern_rgba(in_sz[0], in_sz[1], in_sz[0], in_sz[1])
        sx = float16_round(out_sz[0] / in_sz[0])
        sy = float16_round(out_sz[1] / in_sz[1])
        exact = gl.render_1pass(
            core_src, in_rgba, in_sz, in_sz, out_sz, params={"FILTER_MODE": 0.0, "GAMMA_OUT": 0.0}, defines=["PARAMETER_UNIFORM"]
        )
        assert "vec2 raw_scale = OutputSize / InputSize;" in core_src
        stressed_src = core_src.replace("vec2 raw_scale = OutputSize / InputSize;", f"vec2 raw_scale = vec2({sx!r}, {sy!r});")
        stressed = gl.render_1pass(
            stressed_src, in_rgba, in_sz, in_sz, out_sz, params={"FILTER_MODE": 0.0, "GAMMA_OUT": 0.0}, defines=["PARAMETER_UNIFORM"]
        )
        diff = max_rgb_diff(exact, stressed)
        assert diff <= 1, f"core FP16 scale drift at {in_sz}->{out_sz}: max diff={diff}/255"

    # Exercise the !GL_FRAGMENT_PRECISION_HIGH split-FP16 shader path directly on GPU
    for label, src, params, linear_in in [
        ("core(split-fp16)", core_src, {"FILTER_MODE": 0.0, "GAMMA_OUT": 0.0}, True),
        ("fast(split-fp16)", fast_src, {}, True),
        ("8bfbo-safe(split-fp16)", safe_src, {"FILTER_MODE": 0.0, "GAMMA_MODE": 0.0}, False),
    ]:
        for in_sz, tex_sz, out_sz in [((320, 240), (512, 256), (960, 720)), ((240, 160), (256, 256), (1278, 852))]:
            in_rgba = make_pattern_rgba(in_sz[0], in_sz[1], tex_sz[0], tex_sz[1])
            ref = exact_box_reference_2d(in_rgba, in_sz[0], in_sz[1], tex_sz[0], out_sz[0], out_sz[1])
            got = gl.render_1pass(
                src,
                in_rgba,
                in_sz,
                tex_sz,
                out_sz,
                params=params,
                defines=["PARAMETER_UNIFORM", "SHIMMERLESS_FORCE_SPLIT_FP16"],
                linear_input=linear_in,
            )
            max_err = max(
                max(abs(got[4 * i] - r), abs(got[4 * i + 1] - g), abs(got[4 * i + 2] - b))
                for i, (r, g, b) in enumerate(ref)
            )
            assert max_err <= 1.5, f"{label} {in_sz}->{out_sz}: max_err={max_err:.2f}/255"

    # Strict end-to-end IEEE binary16 simulation of the !GL_FRAGMENT_PRECISION_HIGH centered split-FP16 path
    h = float16_round
    fp16_cases = [
        (320, 960, 512, 0.0, 0.0),
        (240, 480, 256, 0.0, 0.0),
        (256, 640, 256, 0.0, 0.0),
        (240, 640, 256, 0.01, 0.125),
        (160, 427, 256, 0.01, 0.125),
        (240, 1278, 256, 0.01, 0.125),
        (240, 1272, 256, 0.01, 0.125),
        (241, 1279, 256, 0.01, 0.125),
        (320, 1024, 512, 0.01, 0.125),
    ]
    for n_in, m_out, t_sz, w_tol, uv_tol in fp16_cases:
        raw_scale = m_out / n_in
        half_out = floor(0.5 * m_out)
        half_in = floor(0.5 * n_in)
        center_err = half_out - half_in * raw_scale
        qstep = 4.0 if raw_scale >= 8.0 else 8.0
        s_hi = h(floor(raw_scale * qstep) / qstep)
        rem = raw_scale - s_hi
        s_mid = h(floor(rem * 8192.0 + 0.5) / 8192.0)
        s_lo = h(rem - s_mid)
        inv_h = h(n_in / m_out)
        rs_h = h(raw_scale)
        ce_h = h(center_err)
        hi_in_h = h(half_in)
        inv_tex = h(1.0 / t_sz)
        uv_min = h(0.5 * inv_tex)
        uv_max = h(h(n_in - 0.5) * inv_tex)
        max_w_err = 0.0
        max_uv_err = 0.0
        for k in range(m_out):
            a, b = k * n_in / m_out, (k + 1) * n_in / m_out
            ta, tb = floor(a), floor(b)
            ref_u = (ta + 0.5) if (tb <= ta or b == tb) else (tb - 0.5 + (b - tb) / (b - a))
            pix_c = h((k + 0.5) - half_out)
            kc = floor(pix_c)
            tx_c = h(h(kc + ce_h) * inv_h)
            mc = floor(h(tx_c + 0.5))
            mc_hi = h(16.0 * floor(h(mc * 0.0625)))
            mc_lo = h(mc - mc_hi)
            d = h(h(h(h(h(kc - h(mc_hi * s_hi)) - h(mc_lo * s_hi)) - h(mc_hi * s_mid)) - h(mc_lo * s_mid)) + h(0.5 + ce_h))
            d = h(d - h(mc * s_lo))
            half_s = h(0.5 * rs_h)
            adj = (1.0 if d >= half_s else 0.0) - (1.0 if d <= -half_s else 0.0)
            mc = h(mc + adj)
            d = h(d - h(adj * rs_h))
            w = min(1.0, max(0.0, h(d + 0.5)))
            m = h(mc + hi_in_h)
            uv_fp16 = min(uv_max, max(uv_min, h(h(m * inv_tex) + h(h(w - 0.5) * inv_tex))))
            max_w_err = max(max_w_err, abs((m - 0.5 + w) - ref_u))
            max_uv_err = max(max_uv_err, abs(uv_fp16 * t_sz - ref_u))
            if n_in == 240 and m_out == 1278 and k == 1245:
                assert abs(uv_fp16 * t_sz - 233.5) < 1e-4, f"240->1278 col 1245 drifted: {uv_fp16 * t_sz}"
        assert max_w_err <= w_tol, f"Binary16 split fallback {n_in}->{m_out}: max_w_err={max_w_err:.5f} > {w_tol}"
        assert max_uv_err <= uv_tol, f"Binary16 UV fallback {n_in}->{m_out}: max_uv_err={max_uv_err:.4f} > {uv_tol}"
    print("[PASS] Issue #4 FP16 scale immunity + split-FP16 GPU & binary16 simulation (core, fast, 8bfbo-safe)")


def test_float_fbo_canary_fails_loud_on_rgba8(gl: GLContext) -> None:
    lin_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-linearize.glsl").read_text()
    core_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-core.glsl").read_text()
    in_sz, out_sz = (16, 16), (32, 32)
    in_rgba = make_pattern_rgba(in_sz[0], in_sz[1], in_sz[0], in_sz[1])

    ok_out = gl.render_2pass(
        lin_src,
        core_src,
        in_rgba,
        in_sz,
        in_sz,
        out_sz,
        fbo0_float=True,
        pass0_params={"GAMMA_MODE": 0.0},
        pass1_params={"FILTER_MODE": 0.0, "GAMMA_OUT": 1.0},
    )
    assert any(ok_out[i + 1] > 0 for i in range(0, len(ok_out), 4)), "RGBA16F falsely triggered magenta canary"

    err_out = gl.render_2pass(
        lin_src,
        core_src,
        in_rgba,
        in_sz,
        in_sz,
        out_sz,
        fbo0_float=False,
        pass0_params={"GAMMA_MODE": 0.0},
        pass1_params={"FILTER_MODE": 0.0, "GAMMA_OUT": 1.0},
    )
    pixels = {(err_out[i], err_out[i + 1], err_out[i + 2]) for i in range(0, len(err_out), 4)}
    assert pixels == {(255, 0, 255)}, f"Expected solid magenta on RGBA8 fallback, got {pixels}"
    print("[PASS] Modern 2-pass alpha canary: normal on RGBA16F, fails loud (solid magenta) on RGBA8 fallback")


def test_downscale_fallback(gl: GLContext) -> None:
    core_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-core.glsl").read_text()
    safe_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-8bfbo-safe.glsl").read_text()
    in_sz, out_sz = (640, 480), (320, 240)
    buf = bytearray(4 * in_sz[0] * in_sz[1])
    for y in range(in_sz[1]):
        for x in range(in_sz[0]):
            v = int(255 * x / (in_sz[0] - 1))
            off = 4 * (y * in_sz[0] + x)
            buf[off : off + 4] = bytes((v, v, v, 255))

    for label, src, params, defines, linear_in in [
        ("core", core_src, {"FILTER_MODE": 1.0, "GAMMA_OUT": 0.0}, ["PARAMETER_UNIFORM"], True),
        ("8bfbo-safe(gamma2)", safe_src, {"FILTER_MODE": 1.0, "GAMMA_MODE": 1.0}, ["PARAMETER_UNIFORM"], False),
        ("8bfbo-safe(split-fp16)", safe_src, {"FILTER_MODE": 0.0, "GAMMA_MODE": 1.0}, ["PARAMETER_UNIFORM", "SHIMMERLESS_FORCE_SPLIT_FP16"], False),
    ]:
        got = gl.render_1pass(src, bytes(buf), in_sz, in_sz, out_sz, params=params, defines=defines, linear_input=linear_in)
        row = [got[4 * x] for x in range(out_sz[0])]
        assert all(row[i] <= row[i + 1] for i in range(len(row) - 1)), f"{label}: non-monotonic gradient on downscale"
        assert row[0] <= 2 and row[-1] >= 253, f"{label}: unexpected downscale endpoints: {row[0]}..{row[-1]}"
    print("[PASS] Graceful bilinear fallback on downscaling (640x480 -> 320x240) for core and 8bfbo-safe")


def test_luminance_conservation_and_smooth_hq(gl: GLContext) -> None:
    lin_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-linearize.glsl").read_text()
    core_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-core.glsl").read_text()
    safe_src = (ROOT / "shaders_glsl/shaders/sharp-shimmerless-2-8bfbo-safe.glsl").read_text()

    def measure_ripple(w_in: int, w_out: int, mode: str) -> float:
        totals = []
        for col in range(10, 34):
            in_rgba = bytearray(4 * w_in)
            for x in range(w_in):
                v = 255 if x == col else 0
                in_rgba[4 * x : 4 * x + 4] = bytes((v, v, v, 255))
            if mode == "fast":
                out = gl.render_1pass(
                    core_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    params={"FILTER_MODE": 0.0, "GAMMA_OUT": 0.0}, defines=["PARAMETER_UNIFORM"],
                )
            elif mode == "modern_gamma2":
                out = gl.render_2pass(
                    lin_src, core_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    fbo0_tex_size=(256 if w_in <= 256 else 512, 1),
                    pass0_params={"GAMMA_MODE": 0.0}, pass1_params={"FILTER_MODE": 0.0, "GAMMA_OUT": 1.0},
                )
            elif mode == "modern_srgb":
                out = gl.render_2pass(
                    lin_src, core_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    pass0_params={"GAMMA_MODE": 1.0}, pass1_params={"FILTER_MODE": 0.0, "GAMMA_OUT": 2.0},
                )
            elif mode == "safe_gamma2":
                out = gl.render_1pass(
                    safe_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    params={"FILTER_MODE": 0.0, "GAMMA_MODE": 1.0}, defines=["PARAMETER_UNIFORM"], linear_input=False,
                )
            elif mode == "safe_srgb":
                out = gl.render_1pass(
                    safe_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    params={"FILTER_MODE": 0.0, "GAMMA_MODE": 2.0}, defines=["PARAMETER_UNIFORM"], linear_input=False,
                )
            elif mode == "tent_exact":
                out = gl.render_2pass(
                    lin_src, core_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    pass0_params={"GAMMA_MODE": 1.0}, pass1_params={"FILTER_MODE": 1.0, "GAMMA_OUT": 2.0, "SNAP_INT_AXES": 1.0},
                )
            elif mode == "hann_exact":
                out = gl.render_2pass(
                    lin_src, core_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    pass0_params={"GAMMA_MODE": 1.0}, pass1_params={"FILTER_MODE": 2.0, "GAMMA_OUT": 2.0, "SNAP_INT_AXES": 1.0},
                )
            elif mode == "safe_tent_exact":
                out = gl.render_1pass(
                    safe_src, bytes(in_rgba), (w_in, 1), (w_in, 1), (w_out, 1),
                    params={"FILTER_MODE": 1.0, "GAMMA_MODE": 2.0, "SNAP_INT_AXES": 1.0},
                    defines=["PARAMETER_UNIFORM"], linear_input=False,
                )
            else:
                raise ValueError(mode)
            totals.append(sum(srgb_to_linear(out[4 * x] / 255.0) for x in range(w_out)))
        return (max(totals) - min(totals)) / (sum(totals) / len(totals))

    r_fast = measure_ripple(240, 320, "fast")
    r_mod_g2 = measure_ripple(240, 320, "modern_gamma2")
    r_mod_srgb = measure_ripple(240, 320, "modern_srgb")
    r_safe_g2 = measure_ripple(240, 320, "safe_gamma2")
    r_safe_srgb = measure_ripple(240, 320, "safe_srgb")
    assert r_fast > 0.15, f"Expected large sRGB ripple on -non-gamma-fast, got {r_fast:.3f}"
    assert r_mod_g2 < 0.03 and r_safe_g2 < 0.03, f"Fast gamma 2.0 ripple too high: modern={r_mod_g2:.4f}, safe={r_safe_g2:.4f}"
    assert r_mod_srgb < 0.006 and r_safe_srgb < 0.006, f"Exact sRGB ripple too high: modern={r_mod_srgb:.4f}, safe={r_safe_srgb:.4f}"

    r_tent = measure_ripple(320, 1024, "tent_exact")
    r_hann = measure_ripple(320, 1024, "hann_exact")
    r_safe_tent = measure_ripple(320, 1024, "safe_tent_exact")
    assert r_tent < 0.006 and r_hann < 0.006 and r_safe_tent < 0.006

    # Integer axis snap check: 256 -> 1024 (exact 4x) must produce pure 0/255 pixels
    in_rgba = bytearray(4 * 256)
    for x in range(256):
        v = 255 if x % 2 == 0 else 0
        in_rgba[4 * x : 4 * x + 4] = bytes((v, v, v, 255))
    out_snap_2p = gl.render_2pass(
        lin_src, core_src, bytes(in_rgba), (256, 1), (256, 1), (1024, 1),
        pass0_params={"GAMMA_MODE": 0.0}, pass1_params={"FILTER_MODE": 1.0, "GAMMA_OUT": 1.0, "SNAP_INT_AXES": 1.0},
    )
    out_snap_1p = gl.render_1pass(
        safe_src, bytes(in_rgba), (256, 1), (256, 1), (1024, 1),
        params={"FILTER_MODE": 1.0, "GAMMA_MODE": 1.0, "SNAP_INT_AXES": 1.0},
        defines=["PARAMETER_UNIFORM"], linear_input=False,
    )
    assert {out_snap_2p[4 * x] for x in range(1024)} == {0, 255}
    assert {out_snap_1p[4 * x] for x in range(1024)} == {0, 255}

    print(
        f"[PASS] Luminance ripple 240->320: fast={r_fast*100:.1f}%, modern_g2={r_mod_g2*100:.2f}%, "
        f"safe_g2={r_safe_g2*100:.2f}%, safe_sRGB={r_safe_srgb*100:.2f}% | "
        f"320->1024 Tent={r_tent*100:.2f}%, SafeTent={r_safe_tent*100:.2f}%, Hann={r_hann*100:.2f}% | 4x snap exact"
    )


def test_slang_syntax_parity() -> None:
    """Validate Slang shader structure and push-constant parameter parity."""
    for rel in [
        "shaders_slang/shaders/sharp-shimmerless-2-linearize.slang",
        "shaders_slang/shaders/sharp-shimmerless-2-core.slang",
        "shaders_slang/shaders/sharp-shimmerless-2-8bfbo-safe.slang",
        "shaders_slang/shaders/sharp-shimmerless-2-fast.slang",
    ]:
        src = (ROOT / rel).read_text()
        assert "#version 450" in src, f"{rel} missing #version 450"
        assert "#pragma stage vertex" in src and "#pragma stage fragment" in src, f"{rel} missing stage pragmas"
        assert "layout(push_constant) uniform Push" in src, f"{rel} missing Push block"
        assert "layout(std140, set = 0, binding = 0) uniform UBO" in src, f"{rel} missing UBO block"
        assert "layout(set = 0, binding = 2) uniform sampler2D Source;" in src, f"{rel} missing Source sampler"
        push_block = src.split("layout(push_constant) uniform Push", 1)[1].split("}", 1)[0]
        for pname in re.findall(r"#pragma\s+parameter\s+(\w+)", src):
            assert re.search(rf"\bfloat\s+{pname}\b", push_block), f"{rel} parameter {pname} missing from Push block"
    print("[PASS] Slang shader structural & push-constant parameter checks (all 4 shaders)")


def main() -> int:
    gl = GLContext()
    print(f"OpenGL context: {gl.version}")
    test_presets_and_structure()
    test_box_equivalence_and_padding(gl)
    test_8bfbo_safe_linear_parity_and_shadows(gl)
    test_fp16_drift_immunity(gl)
    test_float_fbo_canary_fails_loud_on_rgba8(gl)
    test_downscale_fallback(gl)
    test_luminance_conservation_and_smooth_hq(gl)
    test_slang_syntax_parity()
    print("\nALL VERIFICATION CHECKS PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
