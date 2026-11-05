# patches/

Status of every patch in this directory after the mpv 0.41.0 upgrade.
"Referenced" means it is applied by a `nix/packages/mk-pkg-*/default.nix`.

## Applied

| file | target | status |
|---|---|---|
| `mpv-041-audiounit.patch` | mpv 0.41 | **new** — audio tap + iOS shared `AVAudioSession` refcounting (supersedes `ao_audiounit_tap.patch` + `mpv-audiounit-shared-session.patch`) |
| `mpv-041-bluray-http.patch` | mpv 0.41 | **new** — HTTP/HTTPS Blu-ray streaming, `stream_seek()` bool fix, `.iso`/`.img` autodetection (supersedes `stream_bluray.patch` + `bluray_autodetect_v036.patch`) |
| `ffmpeg-fix-vp9-hwaccel.patch` | FFmpeg 7.0.2 | unchanged, applies |
| `ffmpeg-fix-ios-hdr-texture.patch` | FFmpeg 7.0.2 | unchanged, applies |
| `ffmpeg-fix-dash-base-url-escape.patch` | FFmpeg 7.0.2 | unchanged, applies |
| `ltmain-target-passthrough.patch` | libass | unchanged |

All three applied FFmpeg patches are byte-identical to the copies the
`melodink` reference build applies to FFmpeg 7.0.2, so they are known-good.

## Deliberately not applied

| file | why |
|---|---|
| `ffmpeg-fix-hls-mp4-seek.patch` | written against FFmpeg 6.0; hunks no longer match `libavformat/hls.c` in 7.0.2. `melodink` disables it for the same reason. |
| `ipt_c2_p5.patch` | **obsolete.** It taught mpv 0.36 about Dolby Vision Profile 5 (IPT-PQ-C2) through `enum mp_csp`, which no longer exists. mpv 0.41 delegates colour handling to libplacebo and already ships `PL_COLOR_SYSTEM_DOLBYVISION`, so DOVI/IPTPQc2 is handled natively by `vo=gpu-next`. |
| `mpv-fix-missing-objc.patch` | **obsolete.** mpv 0.41 already calls `add_languages('objc', native: false)` for darwin, and our cross files set `host_machine.system = 'darwin'`. |
| `mpv-remove-libass.patch` | two of its targets (`sub/ass.h`, `sub/ass_types.h`) do not exist in 0.41, and `player/command.c` plus `meson.build` were heavily refactored. Needs a re-port if the libass-free `audio` variant is still required. Note 0.41 makes libass unconditional. |
| `ao_audiounit_tap.patch` | superseded by `mpv-041-audiounit.patch` |
| `mpv-audiounit-shared-session.patch` | superseded by `mpv-041-audiounit.patch` |
| `stream_bluray.patch` | superseded by `mpv-041-bluray-http.patch` |
| `bluray_autodetect_v036.patch` | superseded by `mpv-041-bluray-http.patch`; also structurally malformed on its own ("corrupt patch") |

The superseded and obsolete files are kept for reference only. They are not
referenced by any Nix expression and are not applied to anything.

## Verification method

Every "applies" claim above was produced by running
`git apply --check` against a real, pristine mpv 0.41.0 or FFmpeg 7.0.2 source
tree — not by inspection. For the two newly generated mpv patches the applied
result was additionally compared byte-for-byte (hash equality) against the
intended file.
