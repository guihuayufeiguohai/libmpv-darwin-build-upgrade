# Upgrade to mpv 0.41.0 — change log and remaining work

This tree is `libmpv-darwin-build`, upgraded from **mpv 0.36.0** to **mpv 0.41.0**
with a dependency bump that makes **libplacebo (Dolby Vision / HDR) actually
usable**, which was impossible in the previous configuration.

---

## 1. What changed

### 1.1 `packages.lock.nix`

| package | before | after | note |
|---|---|---|---|
| mpv | 0.36.0 | **0.41.0** | pinned by NAR hash, see below |
| ffmpeg | 6.0 | **7.0.2** | same version the `melodink` reference build uses |
| libplacebo | *(absent)* | **7.349.0** | new; satisfies mpv's `>= 6.338.2` |
| libplacebo 3rdparty | *(absent)* | fast_float 5.2.0, glad 2.0.4, jinja 3.1.2, markupsafe 2.1.2, Vulkan-Headers 1.3.243 | new; vendored submodules are **not** in GitHub source archives |

Everything else (libass 0.17.1, harfbuzz 8.1.1, freetype 2.13.2, fribidi
1.0.13, dav1d 1.2.1, libvpx 1.13.0, libx264, libxml2, mbedtls, uchardet,
libogg, libvorbis, libpng) is intentionally left unchanged: those versions
satisfy mpv 0.41 and are exactly the combination the `melodink` reference
build already ships.

All hashes are real values, taken from upstream lock files
(`melodink-libmpv-darwin-build-main/downloads.lock`) or from nixpkgs
(`mpv-unwrapped`). **No hash in this file is a guess.**

#### Why mpv uses `narHash` instead of `sha256`

`nix/utils/fetch-tarball` used `builtins.fetchurl`, i.e. `sha256` is the hash of
the **compressed tarball**. nixpkgs pins mpv with `fetchFromGitHub`, whose hash
is the **NAR hash of the extracted tree** — a different value for the same URL.

Rather than inventing a tarball hash, `fetch-tarball` now accepts either
`sha256` (legacy, tarball hash) or `narHash` (SRI, extracted-tree hash, handled
via `pkgs.fetchzip`). `packages.lock.nix` uses `narHash` for mpv only, with the
value copied verbatim from nixpkgs' `mpv-unwrapped`.

### 1.2 libplacebo is now a real dependency

This is the substantive part of the "libplacebo / Dolby Vision" requirement.

The old build passed `-Dlibplacebo=disabled` and `-Dvulkan=disabled`, so there
was no `gpu-next` at all — only legacy `vo=gpu`. Since mpv 0.37 libplacebo is a
**hard** dependency (`dependency('libplacebo', version: '>=6.338.2')`, no
`required: false`), and the `libplacebo` meson option no longer exists.

* new package: `nix/packages/mk-pkg-libplacebo`
* `libplacebo` added to `mk-pkg-mpv` `buildInputs` (unconditionally)

### 1.3 mpv build options ported from 0.36 to 0.41

Options that no longer exist in 0.41 were **removed** — leaving them in makes
`meson setup` abort with "unknown option":

`ta-leak-report`, `stdatomic`, `sdl2`, `libplacebo`, `rpi`, `rpi-mmal`,
`vaapi-x-egl`, `win32-internal-pthreads`,
`macos-10-11-features`, `macos-10-12-2-features`, `macos-10-14-features`

Options added in 0.41 were introduced:

`fuzzers`, `aaudio`, `audiotrack`, `avfoundation`, `dmabuf-wayland`,
`videotoolbox-pl`, `x11-clipboard`, `win32-threads`,
`macos-10-15-4-features`, `macos-11-features`, `macos-11-3-features`,
`macos-12-features`

All 100 `-D` options now used are valid 0.41 options.

### 1.4 `Makefile`

`make build` restored `.nix/config/{xcode.path,version.txt}` with
`git checkout --`, which **cannot work in a plain archive without `.git`** — it
silently left the config files dirty. Replaced with an explicit
save/restore in a temp dir.

---

## 2. Patches: what was ported, what is obsolete, what is still missing

All statements below were verified by running `git apply --check` against a real
**mpv 0.41.0 source tree**, not assumed.

### 2.1 Ported — `patches/mpv-041-audiounit.patch`

Replaces the old `ao_audiounit_tap.patch` + `mpv-audiounit-shared-session.patch`
(kept on disk, no longer referenced).

Contents: audio tap callback that hands the PCM about to be played to the
embedder, an optional resampling helper, and iOS shared-`AVAudioSession`
refcounting with a new `audiounit-skip-session-management` option.

Adapted for 0.41 / FFmpeg 7:

* `ao_read_data()` gained parameters (now `..., NULL, true, true`)
* `ca_frames_to_us` → `ca_frames_to_ns`, `mp_time_us` → `mp_time_ns`
* `swr_alloc_set_opts()` (deprecated in FFmpeg 7) → `swr_alloc_set_opts2()`
  with `AVChannelLayout`

Verification: `git apply --check` → 0, `git apply` → 0, and the resulting file
is byte-identical to the intended one.

### 2.2 Obsolete — dropped on purpose

**`ipt_c2_p5.patch`** (Dolby Vision Profile 5 / IPT-PQ-C2 colour decode).
It existed because mpv 0.36's `enum mp_csp` had no Dolby concept, so P5
rendered green. mpv 0.41 no longer has `enum mp_csp` at all (colours are
libplacebo's `pl_color_*`), and its colour-system table already contains:

```c
{"dolbyvision", PL_COLOR_SYSTEM_DOLBYVISION},
```

i.e. DOVI/IPTPQc2 is handled natively by libplacebo through `vo=gpu-next`.
Keeping the patch would mean re-implementing in mpv what libplacebo already
does correctly.

**`mpv-fix-missing-objc.patch`**. mpv 0.41 already calls
`add_languages('objc', native: false)` for darwin in `meson.build`, and the
cross files set `host_machine.system = 'darwin'`, so the condition is met.

**Parts of `bluray_autodetect_v036.patch`**. Its `demux/demux_disc.c` hunk
(`drop_buffers` after `STREAM_CTRL_SEEK_TO_TIME`) is **already in upstream
0.41**, and `bdmv_dir_stream_open` (BDMV directory autodetection) is upstream
too.

**`ffmpeg-fix-hls-mp4-seek.patch`** is no longer applied: it targets FFmpeg 6.0
and does not match `libavformat/hls.c` in 7.0.2. The `melodink` reference build
disables it for exactly the same reason.

The other three FFmpeg patches (`vp9-hwaccel`, `ios-hdr-texture`,
`dash-base-url-escape`) are **unchanged and still applied** — they are
byte-identical to the copies the `melodink` reference applies to FFmpeg 7.0.2,
so they are known-good for 7.0.2.

### 2.3 Ported — `patches/mpv-041-bluray-http.patch`

Supersedes the old `stream_bluray.patch` + `bluray_autodetect_v036.patch`.
Those two were not plain "autodetection": they add **HTTP/HTTPS Blu-ray
streaming**, which is not upstream in 0.41.

What the ported patch does:

* `http_read_cb()` / `open_bd_http()`: `bd_init()` + `bd_open_stream()` with a
  read callback over an mpv stream, so `http(s)://…` Blu-ray images play
* `stream_open_args` with `.sinfo = &stream_info_ffmpeg` and
  `STREAM_ORIGIN_DIRECT`, so the ffmpeg stream is used directly instead of
  autoprobing (autoprobe re-enters `bdmv_dir_stream_open()`, which sits ahead
  of `stream_info_ffmpeg` in the list, and recurses until the stack overflows)
* `if (!stream_seek(...))` — `stream_seek()` returns `bool`, so the original
  `if (stream_seek(...) < 0)` was always false and a failed seek silently read
  from the previous position, corrupting mpegts data
* `bd_seek_time(b->bd, 0)` after `select_initial_title()`, because
  `demux_disc`'s `reset_pts()` rebases the whole timeline onto libbluray's
  current position, so playback otherwise started tens of seconds in
* `.iso` / `.img` autodetection in `bdmv_dir_stream_open()` (0.41 only probes
  BDMV directories, so a plain `.iso` path never reached libbluray)
* `bluray_stream_close()` frees the wrapper stream

Adapted for 0.41: the old patch hooked `destruct()` (gone) and used the raw
`device` string for `bd_open()`; 0.41 wraps it with `mp_get_user_path()` and
the freeing lives in `bluray_stream_close()`. Because `bd` is no longer a
function-scope variable (it is assigned in two branches), the introduced alias
`BLURAY *bd = b->bd;` keeps the rest of the function unchanged.

Verification: `git apply --check` → 0, `git apply` → 0, byte-identical result.

### 2.4 Still missing / needing a decision

**`mpv-remove-libass.patch`.** Two of its targets (`sub/ass.h`,
`sub/ass_types.h`) do not exist in 0.41 and `player/command.c` / `meson.build`
were heavily refactored. mpv 0.41 also makes libass unconditional, so the
`audio` variant now links libass as well (`libass` moved out of the
`variant == "video"` conditional). Re-porting this ~51 KB patch would restore
the libass-free audio build if that is still required.

---

## 3. Known risks

1. **`fftools-ffi` — confirmed broken, now disabled.** The macOS/iOS CI run
   proved this is a hard failure, not a suspicion:

   ```
   mk-pkg-fftools-ffi-iossimulator-arm64-audio> ... 'nb_side_data' is deprecated ...
   mk-pkg-fftools-ffi-iossimulator-arm64-audio> 31 warnings generated.
   mk-pkg-fftools-ffi-iossimulator-arm64-audio> ninja: build stopped: subcommand failed.
   error: Cannot build '...-mk-pkg-fftools-ffi-iossimulator-arm64-audio-9b0d4da0.drv'.
   ```

   `mk-out-libs`, `mk-out-archive-libs` and `mk-out-all` then failed purely as
   downstream consequences.

   Root cause: upstream vendors a fork of FFmpeg's `fftools` from the FFmpeg 6
   era, and the pinned commit `9b0d4da0` is **already its current HEAD**
   (verified against the GitHub API — newest commit 2026-01-11), so there is no
   newer revision to move to. The `melodink` reference build, which also uses
   FFmpeg 7.0.2, dropped this component for exactly the same reason.

   Resolution: `fftools-ffi` is removed from the `encodersgpl` dependency list
   in `nix/packages/mk-out-libs/default.nix`, and
   `nix/packages/mk-pkg-fftools-ffi/targets.nix` now returns `[ ]` so the flake
   no longer publishes a package that cannot build. The package definition and
   its `packages.lock.nix` entry are kept; both files document how to re-enable
   it after a port to FFmpeg 7.

   The rest of that CI run was healthy: FFmpeg 7.0.2 compiled normally for every
   target (`CC libavfilter/…` for macos-amd64, ios-arm64-video-full,
   iossimulator-amd64/arm64), which validates the FFmpeg layer together with the
   project's own `meson.build` / `meson.options` wrapper.
2. **libplacebo is built without Vulkan** (`-Dvulkan=disabled` in mpv, matching
   the reference build). `vo=gpu-next` therefore runs on the OpenGL backend.
   Full DOVI dynamic-metadata tone mapping on Apple platforms ultimately wants
   Vulkan + MoltenVK; that is a separate, larger change (see
   `mpv_kit-main` `docs/ADR/0001-vulkan-render-backend.md`, which had to patch
   libmpv for a Vulkan render backend).
3. **Nothing here has been compiled.** This machine is Windows; the build
   requires macOS + Nix. See §4.

---

## 4. How to verify on macOS

```sh
# 1. build the default target
make

# 2. or a specific target
make TARGET=mk-out-archive-libs-macos-universal-video-default

# 3. inspect the mpv configure log that the derivation keeps
cat result/share/mpv/configure.log | grep -E 'libplacebo|gpu-next|ffmpeg|libass'
```

`configure.log` must show `libplacebo` as **found** and `libass` as found.

To confirm the Dolby Vision path at runtime:

```sh
mpv --vo=gpu-next --target-colorspace-hint file.mkv
```

`vo=gpu-next` requires libplacebo, which is now present; `vo=gpu` (legacy) has
no DOVI support.

---

## 5. Fixes driven by the macOS/iOS CI runs

### 5.1 `fftools-ffi` removed from the build (first CI failure)

See §3.1. Removed from the `encodersgpl` dependency list in
`nix/packages/mk-out-libs/default.nix`, and
`nix/packages/mk-pkg-fftools-ffi/targets.nix` now returns `[ ]` so the flake
stops publishing a package that cannot build.

### 5.2 Swift build enabled on macOS (second CI failure)

Symptom: mpv 0.41 failed on `macos-amd64-audio` while compiling
`osdep/mac/app_bridge.m`; libplacebo 7.349.0 and FFmpeg 7.0.2 had both built
successfully by then.

Cause: `app_bridge.m` contains

```c
#include "osdep/mac/swift.h"
```

and `swift.h` is produced by the custom target in `osdep/mac/meson.build`,
which is only entered when `features['swift']` is true
(`meson.build`: `if features['swift'] and swift_sources.length() > 0`).
The old option list left `-Dswift-build=disabled`, while `-Dcocoa=enabled`
unconditionally pulls `app_bridge.m` into the sources, so the header never
existed.

Fix, matching what the `melodink` reference build does for the same
mpv/FFmpeg combination:

* `-Dswift-build=enabled` added to `MACOS_OPTIONS`
* a `xcrun` shim added to `nativeBuildInputs` on macOS, because mpv resolves
  the toolchain via `xcrun -find swiftc` and `TOOLS/macos-sdk-version.py`, and
  neither works inside the Nix sandbox. The shim answers exactly the three
  queries mpv makes: `-find <tool>`, `--sdk macosx --show-sdk-path` and
  `--sdk macosx --show-sdk-version` (the last one reads `SDKSettings.json`,
  falling back to `SDKSettings.plist`)
* `nix/utils/xctoolchain/swiftc.nix` (already in the tree, previously unused
  here) added to `nativeBuildInputs` on macOS

Note this is required only because `cocoa` is enabled; it is not a new
dependency of mpv 0.41 as such.

