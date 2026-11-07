# Route C — Vulkan / MoltenVK port (iOS **and** macOS)

Status: **stage 1 + stage 2 committed, building on CI**. The existing
OpenGL-based libmpv build on `main` is untouched and keeps producing working
releases; everything here is isolated on the `vulkan-ios` branch.

> macOS note: the build pipeline (glslang / vulkan-headers / vulkan-sdk /
> libplacebo360 / mpv-vulkan) is built for **both** macOS (arm64) and iOS
> (arm64). The **MoltenVK runtime** is only packaged for iOS so far (the
> `MoltenVK-ios.tar` has an ios-arm64 slice only). macOS needs
> `MoltenVK-macos.tar`, whose hash is being fetched; until then the macOS bundle
> ships without it and the README tells you where to drop it.

## Why staged

* `mpv_kit` (the only project shipping a Vulkan `vo=libmpv` backend) builds
  Windows / Linux / macOS — it has no iOS target, so there is no iOS reference.
* `libplacebo`'s Vulkan backend needs a GLSL→SPIR-V compiler (`glslang`), which
  this Nix tree did not build until now.
* Everything must be validated on a macOS runner; this workspace is Windows and
  cannot run `nix build`.

## What is implemented (stage 1 + 2)

All new Nix packages are **isolated** from the existing GL packages — they do
not change the default `mk-out-all` / release outputs.

| File | What it does |
|---|---|
| `packages.lock.nix` | Adds `moltenvk 1.4.2`, `glslang 16.6.0`, `libplacebo360 7.360.1`, `libplacebo360-3rdparty-fast_float 8.3.2`. |
| `nix/packages/mk-pkg-glslang/` | CMake **static** cross-build of glslang 16.6.0 for macOS + iOS (arm64). `ENABLE_OPT=OFF` (no SPIRV-Tools), `ENABLE_HLSL=OFF`, no binaries/tests. |
| `nix/packages/mk-pkg-vulkan-headers/` | CMake install of Vulkan-Headers (1.3.243) + copies `registry/vk.xml` to `share/vulkan/registry/`. |
| `nix/packages/mk-pkg-vulkan-sdk/` | Merges glslang + Vulkan-Headers into one prefix: `lib/*.a`, `include/glslang`, `include/SPIRV`, `include/vulkan`, `share/vulkan/registry/vk.xml`. This is what libplacebo's `-Dvulkan-sdk` wants. |
| `nix/packages/mk-pkg-libplacebo360/` | libplacebo **7.360.1** (the version mpv_kit's Vulkan patches + glslang seds target) built **static** with `-Dvulkan=enabled -Dglslang=enabled -Dopengl=disabled`, plus the two glslang `find_library` seds. 3rdparty: fast_float 8.3.2, glad, jinja, markupsafe, Vulkan-Headers. |
| `nix/packages/mk-pkg-mpv-vulkan/` | mpv 0.41 built with the four `mpv-041-vulkan-000{1,2,4,5}` patches (instead of the GL renderer-selection patch), `-Dvulkan=enabled -Dgl=disabled -Degl=disabled -Dios-gl=disabled -Dshaderc=disabled -Dspirv-cross=disabled -Dvideotoolbox-pl=enabled`. macOS: coreaudio only (cocoa/swift disabled); iOS: audiounit. |
| `nix/packages/mk-out-vulkan/` | Aggregates the Vulkan libmpv stack into a drop-in dir: `lib/libmpv.dylib` (libplacebo + glslang statically linked in), `include/mpv`, `moltenvk/` (iOS), `README.md`. |
| `patches/mpv-041-vulkan-000{1,2,4,5}-*.patch` | mpv_kit patches adding `MPV_RENDER_API_TYPE_VULKAN`, hwdec device extensions, the gpu-next Vulkan render backend, and the active-renderer `get_info`. |
| `.github/workflows/vulkan-ios.yaml` | (stage 1) builds `mk-pkg-moltenvk-ios-arm64` and uploads it. |
| `.github/workflows/vulkan.yaml` | (stage 2) matrix build of `mk-out-vulkan-macos-arm64` and `mk-out-vulkan-ios-arm64`, uploads each as `vulkan-bundle-*.tar.gz`. Triggers on push to `vulkan-ios` and manual dispatch. |

### Key design decisions

* **libplacebo 7.360.1, not 7.349.0.** 7.349.0's `glslang` meson block omits
  `find_library('glslang')`, so it links no glslang frontend → undefined
  symbols. 7.360.1 adds it, and mpv_kit's seds target exactly that line. The GL
  build keeps 7.349.0.
* **Static libplacebo → static libmpv.** libplacebo + glslang are linked into
  `libmpv.dylib`, so the host App only embeds `libmpv.dylib` + `MoltenVK`.
* **`-Dlcms=disabled`** in libplacebo360 (this tree has no lcms2 package; color
  management is not needed for the first DV test).
* **MoltenVK is NOT a build input.** mpv/libplacebo only need Vulkan *headers*
  at compile time; the Vulkan *loader* (MoltenVK) is resolved at runtime by the
  host App. This is why the macOS build works without the macOS MoltenVK hash.

### Patch verification

Done locally against a pristine mpv 0.41.0 tree with `mpv-041-audiounit.patch`
and `mpv-041-bluray-http.patch` already applied: `0001 → 0002 → 0004 → 0005`
all apply cleanly in order. The A-route `mpv-041-libmpv-renderer-selection.patch`
**conflicts** with 0004 and is intentionally not applied here.

## How to build / test

1. Push this branch as `vulkan-ios` to your fork (or it is already there).
2. The `vulkan` workflow builds macOS-arm64 and iOS-arm64 bundles.
3. Download the `vulkan-bundle-ios-arm64` / `vulkan-bundle-macos-arm64`
   artifacts.
4. For iOS: replace your App's libmpv with `lib/libmpv.dylib`, embed
   `moltenvk/MoltenVK.xcframework`, link Metal/CoreVideo/IOSurface/AudioToolbox,
   and rebuild `media_kit_video`'s `TextureHW` for
   `MPV_RENDER_API_TYPE_VULKAN` (stage 3, separate repo).
5. For macOS: same, but drop `MoltenVK-macos.tar`'s
   `MoltenVK/dynamic/MoltenVK.xcframework` into the bundle first.

## Stage 3 — media_kit rendering layer (separate repo/branch)

`TextureHW.swift` (iOS and macOS) currently hard-codes
`MPV_RENDER_API_TYPE_OPENGL` + `mpv_opengl_fbo` + `EAGLContext`. It must be
rewritten to use `MPV_RENDER_API_TYPE_VULKAN` (the private mpv_kit extension):
create `VkInstance`/`VkDevice` on the host, enable `VK_EXT_metal_objects`, bind
each IOSurface as a `VkImage` with `VkImportMetalIOSurfaceInfoEXT`, and pass
`MPV_RENDER_PARAM_VULKAN_INIT_PARAMS` + `MPV_RENDER_PARAM_VULKAN_IMAGE`. The
frame synchronisation (mpv_kit uses an image ring + quarantine + timeline
semaphores) replaces media_kit's three rotating GLES FBOs + `glFlush`.

`MPV_RENDER_PARAM_VULKAN_*` are **private mpv_kit extensions** — the libmpv
patches (0001/0002/0004/0005) and the host code must stay on the same patch
set.

## Stage 4 — App integration

* Embed `MoltenVK.xcframework`; mpv_kit locates it via
  `NSBundle.mainBundle.privateFrameworksPath` (tries `MoltenVK.framework/MoltenVK`,
  `libMoltenVK.dylib`, `libvulkan.1.dylib`).
* Link `Metal.framework`, `CoreVideo.framework`, `IOSurface.framework`
  (+ `CoreAudio`/`AudioToolbox` as appropriate).
* Flutter `TextureHW` returns the IOSurface-backed `CVPixelBuffer`; Flutter's
  Metal compositor samples it directly.
* Keep the OpenGL path for the simulator and as a fallback.

## Risks

1. Khronos has deprecated MoltenVK (community best-effort). Still the only
   iOS option; acceptable for now.
2. No simulator Vulkan build (only real `ios-arm64`).
3. No local compilation — every change validated on the `macos-15` runner;
   expect 2–4 CI rounds for stage 2 (glslang CMake cross + libplacebo/glslang
   discovery are the likely friction points).
4. libmpv and media_kit must move together; an unmodified media_kit on a
   Vulkan-only libmpv will fail to create a render context.
