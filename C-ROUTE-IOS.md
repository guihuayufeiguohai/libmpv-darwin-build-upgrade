# Route C — Vulkan / MoltenVK port for iOS

Status: **stage 1 complete, stages 2–4 designed but not yet built**.
This branch is intentionally isolated from `main`: the existing OpenGL-based
libmpv build is untouched and keeps producing working releases.

## Why staged

There is no existing reference for this combination:

* `mpv_kit` (the only project shipping a Vulkan `vo=libmpv` backend) builds
  **Windows / Linux / macOS only** — it has no iOS target at all.
* `MoltenVK-ios.tar` contains an **ios-arm64 slice only**, no simulator slice.
* `libplacebo`'s Vulkan backend needs a GLSL→SPIR-V compiler (`glslang` or
  `shaderc`), which this Nix tree does not currently build.
* Everything here must be validated on a macOS runner; this workspace is
  Windows and cannot run `nix build`.

Stage 1 therefore delivers only things that are deterministic (a prebuilt
binary unpack + pkg-config + the four mpv patches) and gives us a CI job whose
log tells us whether the Nix wiring is correct before touching the compiler
chain.

## Stage 1 — delivered in this branch

| File | What it does |
|---|---|
| `packages.lock.nix` | Adds `moltenvk = 1.4.2` (`MoltenVK-ios.tar`, sha256 verified locally against the 34,535,424-byte release asset) and `glslang = 16.6.0` (pinned for stage 2). |
| `nix/packages/mk-pkg-moltenvk/default.nix` | Unpacks MoltenVK into a Nix package: `libMoltenVK.a`, Vulkan 1.3.357 headers, `vk_video`, MoltenVK headers, both XCFrameworks, Apache-2.0 license, and a generated `vulkan.pc`. |
| `nix/packages/mk-pkg-moltenvk/targets.nix` | Registers **ios-arm64 only** (the archive has no simulator slice). |
| `patches/mpv-041-vulkan-000{1,2,4,5}-*.patch` | The four mpv_kit patches that add `MPV_RENDER_API_TYPE_VULKAN`, pass imported device extensions to FFmpeg, add the gpu-next Vulkan render backend, and report the active renderer via `get_info`. |
| `.github/workflows/vulkan-ios.yaml` | Builds `mk-pkg-moltenvk-ios-arm64` on `macos-15`, prints the layout, and uploads `moltenvk-ios-arm64.tar.gz` as a downloadable artifact. |

**Patch verification** (done locally against a pristine mpv 0.41.0 tree with
this repo's `mpv-041-audiounit.patch` and `mpv-041-bluray-http.patch`
already applied): `0001 → 0002 → 0004 → 0005` all apply cleanly and in order.
The A-route patch `mpv-041-libmpv-renderer-selection.patch` **conflicts** with
0004 and must NOT be applied on this branch (both rewrite `vo_gpu_next.c` and
`vo_libmpv.c`). It is kept in `patches/` for reference only.

### How to run stage 1

1. Push this branch as `vulkan-ios` to your fork.
2. The `vulkan-ios-stage1` workflow starts automatically.
3. Download the `moltenvk-ios-arm64` artifact from the run page.

Expected log lines:

```
--- vulkan.pc ---
prefix=/nix/store/...-mk-pkg-moltenvk-ios-arm64-1.4.2
...
--- header version ---
#define VK_HEADER_VERSION 357
--- static lib ---
... libMoltenVK.a
```

If `nix build` fails at flake evaluation, the error will name the offending
`mk-pkg-moltenvk` line — send me that log and I will fix the expression.

## Stage 2 — enable Vulkan in libplacebo and mpv (next iteration)

Do this only after stage 1 is green. All changes are gated on
`os == "ios" && arch == "arm64"`.

### 2.1 glslang (new package `nix/packages/mk-pkg-glslang/`)

Needed because `libplacebo`'s Vulkan renderer compiles generated GLSL into
SPIR-V at runtime; without it the build succeeds with a meson warning but
every `pl_pass_create()` fails at runtime.

Build from `packages.lock.nix.glslang` with CMake, mirroring mpv_kit's
`native/build/deps.sh`:

```
cmake -S . -B build -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=<iPhoneOS.sdk> \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF -DENABLE_OPT=OFF \
  -DGLSLANG_TESTS=OFF -DENABLE_GLSLANG_BINARIES=OFF \
  -DENABLE_HLSL=OFF -DGLSLANG_ENABLE_INSTALL=ON
```

`-DENABLE_OPT=OFF` avoids SPIRV-Tools entirely. Install into `$out` and copy
`$out/share/vulkan/registry/vk.xml` (libplacebo needs it for
`-Dvulkan-registry`).

> This is the highest-risk piece: this tree's cross toolchain is meson-centric
> and has no CMake/iOS precedent. Expect one or two CI iterations here.

### 2.2 `nix/packages/mk-pkg-libplacebo/default.nix`

For ios-arm64 only, replace the current options with:

```
-Dvulkan=enabled -Dvk-proc-addr=enabled \
-Dglslang=enabled -Dshaderc=disabled \
-Dvulkan-sdk=<glslang/moltenvk prefix> \
-Dvulkan-registry=<prefix>/share/vulkan/registry/vk.xml \
-Ddovi=enabled -Dlibdovi=disabled
```

Keep `-Dopengl=enabled` for now so a stock media_kit App still renders while
the Dart side is being ported. Add `moltenvk` and `glslang` to
`buildInputs` / `PKG_CONFIG_PATH` so `dependency('vulkan')` resolves through
the generated `vulkan.pc`.

### 2.3 `nix/packages/mk-pkg-mpv/default.nix`

* Apply the four `mpv-041-vulkan-000{1,2,4,5}-*.patch` files **instead of**
  `mpv-041-libmpv-renderer-selection.patch` (comment the latter out).
* Add `-Dvulkan=enabled` for ios-arm64 (keep `-Dvulkan=disabled` for all
  other targets).
* Add `moltenvk` + `glslang` to `buildInputs` and set `PKG_CONFIG_PATH` to
  include `$moltenvk/lib/pkgconfig`.
* Have `configure.log` assert `HAVE_VULKAN=1`; mpv_kit's `build.sh` does this
  because `-Dvulkan=enabled` can silently fall back to disabled when the
  header check fails.

### 2.4 Packaging

Add `MoltenVK.xcframework` to the ios-arm64 `mk-out-xcframeworks` output (or
ship it as a second archive) so the App can embed it. `mpv_kit` links
`libMoltenVK` directly into libmpv on macOS; on iOS the App must also embed
the framework so the host-side `VkInstance` and libmpv use **the same**
MoltenVK implementation.

### 2.5 Acceptance for stage 2

`configure.log` shows `vulkan` found, and `nix build` produces an
`Mpv.xcframework` whose binary exports `mpv_render_context_create` plus the
Vulkan backend symbols. A minimal host that creates a `VkInstance`/`VkDevice`
should then be able to call `mpv_render_context_create` with
`MPV_RENDER_API_TYPE_VULKAN` and get `MPV_ERROR_NONE`.

## Stage 3 — media_kit rendering layer (separate repo/branch)

The rendering layer is the `media_kit_video` sub-package, **not** `media_kit`:

* `media_kit_video/common/darwin/Classes/plugin/VideoOutput.swift` — selects
  `TextureHW` vs `TextureSW`, owns register/resize/render scheduling.
* `media_kit_video/ios/media_kit_video/Sources/media_kit_video/plugin/TextureHW.swift`
  — today hard-codes `MPV_RENDER_API_TYPE_OPENGL`, `mpv_opengl_init_params`,
  `mpv_opengl_fbo`, `EAGLContext`, `CVOpenGLESTextureCache`. This is where
  `TextureGL: resize` and `Cannot get OpenGLES function pointer!` come from.
* `.../plugin/gles/{OpenGLESHelpers,TextureGLESContext}.swift`
* macOS mirror under `media_kit_video/macos/.../plugin/`
* `media_kit_video/ios/media_kit_video.podspec` (currently
  `GL_SILENCE_DEPRECATION`, `-framework Mpv`)
* `media_kit_video/lib/src/video_controller/native_video_controller/`

**Good news**: `TextureHW` already implements
`FlutterTexture.copyPixelBuffer() -> CVPixelBuffer`, and mpv_kit's macOS
backend also uses an IOSurface-backed `CVPixelBuffer` + `FlutterTexture`.
The Flutter compositor interface does not need to change — only the producer
of that pixel buffer does.

Work: create `VkInstance`/`VkDevice` on the host, enable
`VK_EXT_metal_objects`, bind each IOSurface as a `VkImage` with
`VkImportMetalIOSurfaceInfoEXT`, pass
`MPV_RENDER_PARAM_VULKAN_INIT_PARAMS` + `MPV_RENDER_PARAM_VULKAN_IMAGE`, and
rebuild the frame synchronisation (mpv_kit uses an image ring + quarantine +
timeline semaphores; media_kit currently rotates three GLES FBOs with
`glFlush`). Add `Metal`, `CoreVideo`, `IOSurface`, `MoltenVK`, Vulkan headers
and `volk` to the podspec / `Package.swift`, plus
`VK_USE_PLATFORM_METAL_EXT`.

Note: `MPV_RENDER_PARAM_VULKAN_*` are **private mpv_kit extensions**, not
upstream libmpv API. The libmpv patches and the host code must stay on the
same patch set.

Version alignment: your App currently resolves `media_kit_video 1.3.1`, whose
Darwin classes live in `ios/Classes/`. The fork's `main` is the Pub-workspace
layout (`2.0.1`) shown above. Pick one and stay on it.

## Stage 4 — App integration

* Embed `MoltenVK.xcframework` (mpv_kit locates it via
  `NSBundle.mainBundle.privateFrameworksPath`, trying
  `MoltenVK.framework/MoltenVK`, `libMoltenVK.dylib`, `libvulkan.1.dylib`).
* Link `Metal.framework`, `CoreVideo.framework`, `IOSurface.framework`.
* Use a `FlutterTexture` returning the IOSurface-backed `CVPixelBuffer`;
  Flutter's Metal compositor samples it directly.
* Raise the deployment target (MoltenVK 1.4.2 needs a recent iOS; verify
  against `MoltenVK.xcodeproj` deployment settings).

## Risks to keep in mind

1. **Khronos has deprecated MoltenVK** (community best-effort maintenance).
   It is still the recommended option for iOS, but this is not a stable
   long-term foundation.
2. **No simulator build**: only `ios-arm64` real devices can use Vulkan.
   Keep the OpenGL path for simulator and macOS.
3. **No local compilation**: every Nix/CMake/meson change here must be
   validated on the `macos-15` runner. Expect 2–4 CI rounds for stage 2.
4. **Two repos must move together**: a Vulkan-only libmpv with an unmodified
   media_kit would simply fail to create a render context. Ship both, or keep
   OpenGL enabled in libmpv during the transition.
5. Route A (the GL gpu-next patch on `main`) remains available as a fallback;
   `MPV_LIBMPV_RENDERER=gpu` restores the legacy gl_video path without a
   rebuild.
