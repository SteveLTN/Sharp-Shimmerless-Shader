# Rocknix Quirks

This reference records Rocknix-specific behavior discovered while deploying Sharp-Shimmerless. It supplements the generic [RetroArch handheld agent guide](RETROARCH-HANDHELD-AGENT-GUIDE.md); none of these paths or behaviors should be assumed on another operating system.

Add new platforms as separate sections. Record the Rocknix version, hardware, mount evidence, configuration regeneration behavior, persistent override mechanism, and whether runtime rendering was visually verified.

## RK3326

The following details were verified on one Rocknix `20261101` RK3326 handheld on 2026-11-25. Future Rocknix images can differ.

### Hardware and observed compatibility

- ARM Mali-G31 with OpenGL ES 3.2 and Vulkan 1.3 support.
- RetroArch built with GLSL, Slang, OpenGL, OpenGLES, and Vulkan support.
- Local GPU verification passed, including the two-pass RGBA16F pipeline and magenta canary test.
- Legacy `gl` plus the standard two-pass GLSL preset **did not work** on this image. RetroArch logged that floating-point FBOs were unsupported, fell back to UNORM, and displayed solid magenta.
- Vulkan detected the Mali-G31, and the Vulkan/Slang configuration was installed. Runtime visual validation is still required; do not describe it as confirmed working solely from driver detection.
- The one-pass GLSL fast fallback is the compatibility option when the two-pass pipeline is unavailable, but the updated fallback preset also needs an on-device visual check.

### TF1 and TF2 storage mapping

On this particular device:

| Card | Mount evidence | Relevant content |
| --- | --- | --- |
| **TF1 / system card** | `/dev/mmcblk1p2` at `/storage`, ext4 | Rocknix/RetroArch configuration, custom menu references, and backups. |
| **TF2 / game card** | `/dev/mmcblk0p1` at `/storage/games-external` and `/storage/roms`, exFAT | ROMs and the actual Sharp-Shimmerless tree. |

This mapping is not a generic TF1/TF2 rule. Verify `/proc/mounts` on each device.

TF1 configuration paths:

```text
/storage/.config/retroarch/retroarch.cfg
/storage/.config/system/configs/system.cfg
/storage/.config/profile.d/091-ui_shader
/storage/shaders/
/storage/backup/
```

TF2 shader path on the running handheld:

```text
/storage/roms/shaders/Sharp-Shimmerless-Shader/
```

The same directory can appear as:

```text
/storage/games-external/roms/shaders/Sharp-Shimmerless-Shader/
```

When TF2 is mounted on a desktop, its path is:

```text
<TF2>/roms/shaders/Sharp-Shimmerless-Shader/
```

Updating TF2 is sufficient when names and reference paths are unchanged. Changing the selected preset, video driver, or Rocknix menu filter requires TF1 changes.

### Launch chain and shader menu

```text
EmulationStation
  → /usr/bin/runemu.sh
  → /usr/bin/setsettings.sh
  → generated /tmp/.retroarch.cfg
  → RetroArch
```

`setsettings.sh` reads the Rocknix `shaderset` selection and generates RetroArch settings plus `--set-shader /tmp/shaders/<preset>`. Therefore `/tmp/.retroarch.cfg` is not a persistent editing target.

`/tmp/shaders` is an overlay combining built-in shaders with persistent custom references from `/storage/shaders` on TF1. `/usr/bin/getshaders` scans it for the extension selected by `UI_SHADER`.

For Vulkan/Slang, `/storage/shaders/sharp-shimmerless.slangp` contains:

```text
#reference "/roms/shaders/Sharp-Shimmerless-Shader/shaders_slang/sharp-shimmerless.slangp"
```

For legacy GLSL, `/storage/shaders/sharp-shimmerless.glslp` contains:

```text
#reference "/roms/shaders/Sharp-Shimmerless-Shader/shaders_glsl/sharp-shimmerless.glslp"
```

The standard Vulkan/Slang configuration used for this example is:

```ini
# /storage/.config/retroarch/retroarch.cfg
video_driver = "vulkan"
```

```ini
# /storage/.config/system/configs/system.cfg
global.shaderset=sharp-shimmerless.slangp
gba.shaderset=sharp-shimmerless.slangp
nes.shaderset=sharp-shimmerless.slangp
```

```ini
# /storage/.config/profile.d/091-ui_shader
UI_SHADER="slangp"
```

The per-system entries preserve this device's existing global/GBA/NES setup; they are not required on every installation.

### Boot-time vendor overrides

**Direct edits to the files above are not sufficient on the reference RK3326 image.** Rocknix reapplies two vendor quirks at every boot:

- `/usr/lib/autostart/quirks/platforms/RK3326/060-game_settings` forces `video_driver = "gl"`.
- `/usr/lib/autostart/quirks/platforms/RK3326/091-ui_shader` rewrites `UI_SHADER="glslp"`.

This behavior explains why manually selecting Vulkan/Slang can revert to GL/GLSL after reboot. Once the frontend returns to GLSL mode, it can also remove incompatible saved shader selections.

Do not modify the read-only vendor quirks themselves.

### Persistent custom-autostart override

Rocknix runs executable user scripts from `/storage/.config/autostart/` **after** the platform quirks and before starting EmulationStation. Install the persistent Vulkan/Slang override as `/storage/.config/autostart/090-sharp-shimmerless`:

```bash
#!/bin/bash
# RK3326 vendor quirks force GL/GLSL during boot; reapply the requested Vulkan/Slang pipeline afterward.
. /etc/profile

sed -i "/^video_driver =/c\\video_driver = \"vulkan\"" /storage/.config/retroarch/retroarch.cfg
cat > /storage/.config/profile.d/091-ui_shader <<SETTINGS
UI_SHADER="slangp"
SETTINGS
set_setting global.shaderset sharp-shimmerless.slangp
set_setting gba.shaderset sharp-shimmerless.slangp
set_setting nes.shaderset sharp-shimmerless.slangp
```

Back up the affected files before installing the override, run `bash -n` on it, and make it executable. A restart of EmulationStation or the device is needed to reload the frontend's shader-menu environment.

An already-running EmulationStation process may retain the previous `UI_SHADER` environment until restarted, while the next game launch still reads the saved shader selection. For reliable menu behavior and to prevent the frontend from removing mismatched selections, restart the frontend after installing the override.
