# Agent Guide: RetroArch Handheld Deployment

This guide is part of [SteveLTN/Sharp-Shimmerless-Shader-2](https://github.com/SteveLTN/Sharp-Shimmerless-Shader-2). Use the shader sources and presets from that repository, and follow this guide to recommend, install, and configure them. For Rocknix devices, also read [the Rocknix quirks guide](https://github.com/SteveLTN/Sharp-Shimmerless-Shader-2/blob/main/ROCKNIX-QUIRKS.md).

This guide is for AI agents and humans installing or updating Sharp-Shimmerless-2 on RetroArch handhelds and similar embedded devices. It is operating-system agnostic: discover the device's actual layout instead of assuming Rocknix paths, card numbering, account names, or configuration mechanisms.

Platform-specific behavior lives in separate [quirks references](#platform-specific-quirks), which provide verified examples rather than universal layouts.

## Getting started from the README prompt

The owner may provide only the README prompt, without a device name, OS version, RetroArch version, IP address, or connection method. Do not require the owner to fill in a template.

Begin read-only by discovering what is accessible from your environment:

- Determine whether RetroArch is installed on the local computer.
- Look for already-connected devices and available device-control tools.
- Check for existing, authenticated remote access without guessing credentials.
- Identify attached removable storage only when direct card access is being used.
- Once device access is available, identify the hardware, OS and version, RetroArch version and capabilities, active video driver, display resolution, frontend, launch chain, and persistent storage.

Use an available safe control method rather than assuming SSH. If no device is accessible, briefly explain the supported connection options and ask the owner which one to use. Ask only for access information that cannot be discovered; never guess passwords or expose credentials.

Explain the available presets and recommend one based on the discovered hardware, display, driver, and performance constraints. Obtain approval before installing files or changing configuration.

## Non-negotiable safety rules

- Start read-only. Identify the OS, RetroArch version/features, active processes, mounts, free space, existing driver, shader selection, and launch mechanism before changing anything.
- Never kill or close an active game without the owner's approval. Check for both `retroarch` and `retroarch32` with `pgrep -x` where available; a broad `ps | grep` can match the inspection command itself.
- Back up the live shader directory and every configuration file before editing it. Device configuration can contain Wi-Fi credentials, passwords, and personal data. Do not print whole configuration files, commit them, or include secrets in reports. Keep backups restrictive.
- Stage uploads and verify checksums before replacing the live directory. Keep the backup until the visual launch test succeeds.
- Determine whether the frontend generates RetroArch configuration at launch. Do not edit a generated temporary config as though it were persistent.
- Do not reboot, restart the frontend, change the video driver, or select the compatibility fallback without the owner's approval when those actions exceed the requested work.
- Do not claim driver compatibility from file checks, shader compilation, or GPU feature detection alone. The final test is a normal game image on the device, not a black or magenta screen.

## Choose the correct shader variant

Select the shader language from RetroArch's active video driver:

| RetroArch video driver | Shader directory | Notes |
| --- | --- | --- |
| `vulkan` | `shaders_slang/` | Preferred where the device and core work correctly with Vulkan. |
| `glcore` | `shaders_slang/` | Use Slang rather than the legacy GLSL presets. |
| `metal`, `d3d11`, `d3d12` | `shaders_slang/` | Relevant to non-Linux RetroArch systems using the same shader package. |
| `gl` / OpenGL ES | `shaders_glsl/` | Legacy GLSL path. Use `-gamma-8bfbo-safe` (or `-non-gamma-fast`) when float FBOs are unavailable. |

Then select from the 4 symmetrical presets (identical names in both `shaders_glsl/` and `shaders_slang/`):

| Preset | Passes | Float FBO | Intended use |
| --- | ---: | :---: | --- |
| `sharp-shimmerless-2-gamma-modern` | 2 | Yes | Default for modern drivers (`vulkan`, `glcore`, `metal`, `d3d11/12`, desktop `gl`) on 640×480 / general displays. |
| `sharp-shimmerless-2-gamma-8bfbo-safe` | 1 | No | Recommended linear-light preset for legacy `gl` / GLES drivers without float FBOs (adaptive 1/2/4-tap fast γ = 2.0, zero FBO overhead). |
| `sharp-shimmerless-2-non-gamma-fast` | 1 | No | Maximum-speed 1-tap sRGB path for ultra-constrained GPUs. |
| `sharp-shimmerless-2-gamma-modern-hq` | 2 | Yes | Smooth Tent/Hann filter with integer-axis snap for high-PPI displays on modern drivers. |

The two-pass `-gamma-modern` presets set `float_framebuffer0 = true`. On legacy `gl`, RetroArch may silently substitute an 8-bit UNORM intermediate. The shader detects this with an alpha canary and intentionally displays solid magenta rather than crushing dark colors.

A magenta screen means the current driver/FBO path is incompatible with the 2-pass `-gamma-modern` preset. It does not identify a defective shader file. Confirm the driver and logs, then offer to switch to **`sharp-shimmerless-2-gamma-8bfbo-safe.glslp`** (stays on `gl` with linear-light gamma) or switch to Slang with `vulkan` / `glcore`.

## Discover the device before deployment

Do not assume that `retroarch.cfg` is the only or authoritative configuration. Frontends can combine a base config, core/content overrides, generated append configs, and command-line options.

Record:

1. **OS and hardware:** OS release, architecture, SoC/GPU, and available RAM/storage.
2. **RetroArch capabilities:** video drivers and shader backends compiled into the installed binary.
3. **Active configuration:** current `video_driver`, shader directory, selected preset, and any per-core/per-game overrides.
4. **Launch chain:** how the frontend starts RetroArch and whether it regenerates configuration or adds `--set-shader`.
5. **Storage:** which mounts are read/write, which removable card contains games/shaders, and where configuration persists.
6. **Runtime state:** whether RetroArch is running and whether a visual test can be performed safely.

Useful commands when available over SSH:

```sh
cat /etc/os-release
uname -a
retroarch --version
retroarch --features
pgrep -a -x retroarch || true
pgrep -a -x retroarch32 || true
df -h
cat /proc/mounts
```

For Vulkan devices, `vulkaninfo --summary` can confirm that a real driver and physical device are visible. This proves availability, not that the complete RetroArch/core/shader combination will render correctly.

Inspect only relevant configuration keys, for example:

```sh
grep '^video_driver = ' <retroarch-config>
grep -E 'shaderset|shader' <frontend-settings>
```

Do not dump an entire frontend configuration file into terminal output or an agent transcript.

## Persistent installation model

A generic installation has up to three layers:

1. **Shader tree:** the persistent `shaders_glsl/` and `shaders_slang/` directories. Place them somewhere RetroArch can read after every reboot.
2. **Selected preset:** the `.glslp` or `.slangp` chosen in RetroArch or by the frontend.
3. **Frontend integration (optional):** a reference preset, menu registration, generated config, or launch argument used by the device's OS.

A normal RetroArch installation can load a preset directly from the persistent shader tree. A frontend-managed device may instead require a small reference preset in its own shader directory. Reference indirection is frontend-specific; do not assume every RetroArch distribution needs it.

When updating files without changing preset names or paths, normally only the shader tree needs replacement. Driver changes, preset selection changes, and frontend menu changes require separate persistent configuration updates.

## Controlling the device with an agent

Choose from the methods available in the current environment. SSH is one option, not a prerequisite.

### Local RetroArch installation

When the agent is running on the same computer as RetroArch, inspect the local installation, process state, configuration, overrides, and shader directories directly. Account for distribution-specific packaging such as Flatpak, Snap, or portable installations. Do not assume that all RetroArch setups use the same configuration path.

### Existing device-control or remote-access tools

Use an already-available device-control tool, authenticated remote shell, or platform integration when appropriate. Do not install a remote agent, enable a new remote-access service, or weaken device security without the owner's approval.

For Android devices, an existing authorized ADB connection may provide shell and file access. Confirm package names, application-specific storage, and Android storage restrictions before modifying files.

### SSH/SCP/SFTP

Use SSH for a network-accessible device when credentials or an authenticated connection already exist. Use the account supplied or confirmed by the owner; do not assume `root` or guess passwords.

SSH supports read-only discovery, staged uploads, checksum verification, and configuration updates. An mDNS name may work, but use the confirmed LAN address if name resolution is unreliable. Do not change VPN or network settings without approval.

### Direct card editing

For offline maintenance:

1. Shut down the handheld cleanly before removing storage.
2. Identify partitions by labels, filesystems, and contents—not slot numbers.
3. Back up every file being replaced.
4. Stage the replacement and verify checksums.
5. Locate frontend configuration, which may reside on another partition.
6. Preserve permissions where applicable and safely eject the media.

Direct card access may not reveal the installed RetroArch version, runtime driver support, or active processes. Record those details as unknown until they can be verified on the device.

### Shared folders and other file-only access

A mounted network share or synchronized folder can be used to copy shader files when it exposes the correct RetroArch directories. File-only access cannot establish the complete runtime configuration or prove rendering compatibility. Use it only when the destination and persistence are clear, and leave runtime inspection and visual validation as explicit follow-ups.

Regardless of the method, start read-only, back up replaced files, verify checksums, preserve persistent configuration, and request an on-device visual test before declaring success.

## Safe deployment workflow

1. **Validate the source.** From the repository root, run:

   ```sh
   python3 tests/verify_shaders.py
   ```

   This is a standalone GPU verification script, not a `unittest` suite; `python3 -m unittest discover` does not run it.

2. **Inspect the target.** Record the discovery information above and confirm that RetroArch is closed before replacing live configuration.

3. **Back up.** Use a timestamped backup outside the upload staging directory. Include the current shader tree, selected presets/reference files, RetroArch configuration, and frontend settings that will change.

4. **Stage on the destination filesystem.** Upload `shaders_glsl`, `shaders_slang`, `README.md`, and `LICENSE.txt` without touching the live tree. Generate a SHA-256 manifest from the source files.

5. **Verify before swapping.** Check every staged checksum, the selected preset's pass count, and every referenced shader path.

6. **Replace with rollback ready.** Move the live directory aside, move staging into place, and verify again. Restore the old directory immediately if verification fails. Remove temporary files only after the live copy passes.

7. **Update persistent settings as one pipeline.** Keep the video driver, shader language, preset filename, frontend menu filter, and launch-time override behavior consistent.

8. **Verify configuration without exposing secrets.** Check only relevant keys, preset/reference paths, and checksums. Do not assume a running frontend has reloaded environment variables or menu lists.

9. **Request a visual test.** Ask the owner to launch a suitable game normally. A normal image is required before declaring success. Note any one-time shader compilation delay, persistent performance problem, black screen, or magenta canary.

10. **Report the result.** List changed paths, backup location, test/checksum results, and remaining runtime uncertainty. Do not commit device configuration, credentials, logs, or backups to this repository.

## Platform-specific quirks

Keep OS-, frontend-, and hardware-specific behavior out of this generic workflow. Consult the relevant quirks reference after discovering the target platform, and add new references as separate files so they can grow independently.

- [Rocknix quirks](ROCKNIX-QUIRKS.md): currently documents the verified RK3326 storage layout, legacy `gl` limitation, launch-time configuration generation, boot-time vendor overrides, and persistent custom-autostart workaround.

A quirks reference should identify the exact OS version and hardware tested, provide mount/configuration evidence, distinguish direct edits from boot-persistent settings, and record whether runtime rendering was visually verified.
