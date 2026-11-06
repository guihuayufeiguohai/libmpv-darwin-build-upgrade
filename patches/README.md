# patches/

Status of every patch in this directory after the mpv 0.41.0 upgrade.
"Referenced" means it is applied by a `nix/packages/mk-pkg-*/default.nix`.

## Applied

| file | target | status |
|---|---|---|
| `mpv-041-audiounit.patch` | mpv 0.41 | **new** — audio tap + iOS shared `AVAudioSession` refcounting (supersedes `ao_audiounit_tap.patch` + `mpv-audiounit-shared-session.patch`) |
| `mpv-041-bluray-http.patch` | mpv 0.41 | **new** — HTTP/HTTPS Blu-ray streaming, `stream_seek()` bool fix, `.iso`/`.img` autodetection plus a `bdmv-http` stream handler so `https://…/x.iso` reaches libbluray instead of being probed by libavformat (supersedes `stream_bluray.patch` + `bluray_autodetect_v036.patch`) |
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

## Note on `mpv-041-bluray-http.patch` scope

An earlier revision of this patch only added the HTTP reader inside
`stream_bluray.c` and the `.iso`/`.img` test in `bdmv_dir_stream_open()`. That
is not enough: `bdmv_dir_stream_open()` is registered for the `file` and `""`
protocols only, so a URL such as `https://host/123.iso` never reached it and
fell through to `stream_info_ffmpeg`. libavformat then probed the UDF
filesystem as raw MPEG-PS (`Found 'mpeg' at score=52`), which plays as a black
screen with a duration in the tens of hours.

The current version registers a dedicated `stream_info_bdmv_http` for the
`http`/`https` protocols, placed ahead of `stream_info_ffmpeg` in
`stream/stream.c`. It rejects well-known media/playlist/audio/subtitle
extensions by suffix before touching the network, so ordinary HTTP media
(including `.m3u8` HLS) is unaffected, and it returns `STREAM_UNSUPPORTED` on
any failure so libavformat still gets its chance.

## Blu-ray playback always started mid-title (fix in the same patch)

Symptom: both local and HTTP ISOs began playing 10-30 s in instead of at 0,
the OSD clock was offset, and `seek 0` did not reach the beginning. Reproduced
from a debug log:

```
[disc] reset to time: 12.716444              # on open
[disc] seek to: 0.000000                     # user seeks to 0
[disc] reset to time: 24.771200              # lands at 24.77 anyway
```

Root cause: `bd_tell_time()` and `bd_seek_time()` both operate on libbluray's
**playlist** timeline, whose zero point is the start of the playlist — not the
start of the selected title. A title's first clip normally begins at a non-zero
playlist time (CLPI `presentation_start_time`; the first PES packet of a clip
does not carry PTS 0). `STREAM_CTRL_GET_CURRENT_TIME` returned that value as if
it were the playback position, `demux_disc.c:reset_pts()` adopted it as the
time base, and `d_read_packet()` then shifted every timestamp by it.

Fix: `stream_bluray.c` now records the offset once and applies it
symmetrically:

- `GET_CURRENT_TIME`: playlist time **minus** offset, clamped at 0
- `SEEK_TO_TIME`: playback time **plus** offset, clamped at 0

No change to `demux_disc.c` was needed, so DVD and CD playback is untouched.

**Timing matters.** The first version of this fix sampled the offset in
`select_initial_title()`, immediately after `bd_select_title()`, which logged
`Title starts at playlist time 0.000000` and did nothing: `bd_tell_time()` keeps
returning 0 until libbluray has actually consumed the first clip block.
`demux_disc.c:d_open()` reads one byte before calling `reset_pts()`, so it saw
the real value (12.716444) while our offset was still 0. The sample therefore
had to move into the first successful `bd_read()` inside
`bluray_stream_fill_buffer()`, guarded by `time_offset_known`.
`STREAM_CTRL_SET_CURRENT_TITLE` clears that flag so the next title re-samples.

## Seeking was broken for Blu-ray over HTTP (fix in the same patch)

Symptom: after the offset fix, dragging the progress bar did nothing at all on
HTTP ISOs, and the log filled up with H.264 errors (`non-existing PPS 0
referenced`, `error while decoding MB ...`) because the decoder was fed packets
from the wrong position.

```
[bdmv-http] stream level seek from 167346176 to 4
[e][bdmv-http] Cannot seek backward in linear streams!
```

Root cause: the outer stream that libbluray feeds has no meaningful byte address
space — its content is whatever `bd_read()` de-multiplexes, and repositioning is
done exclusively through `bd_seek_time()`. mpv nevertheless performs raw byte
seeks on it: `demux_disc.c:d_seek()` calls
`p->slave->desc->drop_buffers(p->slave)` right after `STREAM_CTRL_SEEK_TO_TIME`,
and `demux_drop_buffers_lavf()` begins with `av_seek_frame(avfc, -1, 0, 1)`,
which reaches `stream_seek(outer, 0)`. With `seekable == false` that fails hard
and leaves the position state inconsistent. Local `.iso` playback never hit this
only because `stream_file` happens to be seekable.

Fix: `bluray_stream_open_internal()` now sets `s->seekable = true` and installs
`bluray_stream_seek()`, a shim that accepts the request, returns success, and
pins the logical position to `delivered_pos` (the number of bytes `bd_read()`
has produced so far). Seeks therefore never reach the transport and never fail.
This mirrors `stream_memory.c`, which also answers every seek with a bare
`return 1`.

Note that this does not make a Blu-ray seekable by byte offset — it only stops
mpv's bookkeeping from aborting. Actual repositioning still goes through
`bd_seek_time()` with the offset applied.
