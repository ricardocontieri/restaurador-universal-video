# Case study: Unicode-safe concat after frame-exact segmented restoration

## Summary

This case records a real regression found while completing a four-master archival video batch. It is intentionally sanitized: no private media, personal filesystem root, or family-identifying content is included.

Two long masters required frame-exact treatment of baked-in pillarbox regions. Their segmented renders were successful, but the first concat attempt failed because a Unicode directory name was corrupted inside FFmpeg's concat list. The final fix changed the concat list to use relative ASCII-only segment paths while keeping the Unicode root path outside the text list.

After the fix, both segmented masters passed concat, audio mux, exact frame-count validation and smoke decode. The batch completed 4/4.

## Environment observed in the real batch

- Windows
- PowerShell 7.6.5
- FFmpeg 9.0 full build
- H.264 output at 1920x1080, 30 fps
- NVIDIA NVDEC/CUDA -> NVENC available for normal segments
- `libvidstab`/CPU-side filtering in the restoration pipeline

This case is about path handling and deterministic resume behavior, not about a requirement for that exact hardware.

## Batch shape

The completed batch had four final masters:

| Master | Final behavior | Frame-exact pillar intervals | Review intervals |
|---|---:|---:|---:|
| 01 | Existing validated master reused | n/a | n/a |
| 02 | Segmented render | 45 | 0 |
| 03 | Segmented render | 46 | 0 |
| 04 | Existing validated master reused | n/a | n/a |

For the two segmented masters:

- Master 02: 116,871 frames, 85 total timeline segments, 45 pillar segments.
- Master 03: 107,946 frames, 88 total timeline segments, 46 pillar segments.
- Combined: 173 rendered/reused timeline segments and 91 frame-exact pillar intervals.
- Final manual-review count reported by the pipeline: 0.

## The failure

The first implementation generated an FFmpeg concat list containing absolute paths. The source/work directory contained a Unicode character in one directory name.

The concat list was written in a way that caused that directory name to be represented incorrectly. FFmpeg then attempted to open a path equivalent to:

```text
D:/archive/Travel/Su??a/.../SEGMENTOS/001_NORMAL_0_1190.mp4
```

and failed with the equivalent of:

```text
Impossible to open '.../Su??a/.../SEGMENTOS/001_NORMAL_0_1190.mp4'
Error opening input: Invalid argument
```

The individual segment files themselves were valid.

## Why this was not a codec/stream compatibility problem

Before changing concat behavior, representative segments were inspected with FFprobe. The tested segments shared the expected stream characteristics:

```text
codec_name=h264
profile=High
width=1920
height=1080
pix_fmt=yuv420p
level=41
r_frame_rate=30/1
avg_frame_rate=30/1
time_base=1/15360
start_pts=0
start_time=0.000000
```

Their frame counts also matched the intended frame ranges. Examples from the real run included:

```text
001_NORMAL...  -> 1190 frames
002_PILLAR...  -> 245 frames
003_PILLAR...  -> 150 frames
004_NORMAL...  -> 9281 frames
005_PILLAR...  -> 1864 frames
006_NORMAL...  -> 3509 frames
```

This isolated the failure to path/list handling rather than H.264 parameters or timeline construction.

## Fix

The corrected implementation writes FFmpeg concat entries using paths relative to the work directory, for example:

```text
file 'SEGMENTOS/001_NORMAL_0_1190.mp4'
file 'SEGMENTOS/002_PILLAR_1190_1435.mp4'
file 'SEGMENTOS/003_PILLAR_1435_1585.mp4'
```

The Unicode-containing root directory is supplied to FFmpeg through the process working directory / command-line path handling and never needs to be serialized into the concat text file.

The implementation also validates the generated relative paths before concat and rejects paths that are rooted, escape the intended directory, or contain suspicious replacement artifacts.

## Resume behavior was part of the fix

A key requirement was **not** to rerender already-valid segments after discovering the concat bug.

On the corrected run, Master 02 resumed all 85 previously completed segment checkpoints:

```text
[SEG 001/085] RESUME ...
...
[SEG 085/085] RESUME ...
[CONCAT] lista relativa ASCII: SEGMENTOS/<arquivo>; caminho Unicode da pasta não entra no TXT.
```

It then performed only the remaining concat/mux/validation stages.

Master 03 likewise used its existing frame-exact refinement checkpoint and completed its segment plan without invalidating prior validated work.

This is an important project rule: a late-stage packaging/path failure must not force expensive image reprocessing when segment artifacts have already been independently validated.

## Final validation

After the Unicode-safe concat change:

### Master 02

```text
[CONCAT] remontando vídeo por stream-copy...
[MUX] anexando áudio original sem recompressão...
[VALIDAÇÃO] ffprobe + frame count + smoke início/meio/fim.
[OK] OK_FRAME_EXATO | exatos 45 | revisar 0
```

### Master 03

```text
[CONCAT] remontando vídeo por stream-copy...
[MUX] anexando áudio original sem recompressão...
[VALIDAÇÃO] ffprobe + frame count + smoke início/meio/fim.
[OK] OK_FRAME_EXATO | exatos 46 | revisar 0
```

The overall run ended with:

```text
CONCLUÍDO SEM ERROS
```

and all four final masters present.

## Regression requirements

Future changes to concat or checkpoint handling should preserve these properties:

1. Unicode characters may exist anywhere in the parent/root directory.
2. FFmpeg concat text files should use safe relative paths whenever possible.
3. Segment filenames should remain deterministic and frame-range based.
4. A failed concat must not invalidate completed segment checkpoints.
5. Stream-copy concat must not change the expected total frame count.
6. Final validation must include FFprobe, exact frame count and smoke decode.
7. A successful final master should remain resumable/skippable on subsequent runs.

## Why this case matters

This failure appeared only after all expensive segment rendering had completed. Without robust checkpoints and a Unicode-safe concat strategy, a one-line path-encoding defect could have caused hours of unnecessary rerendering.

The case therefore validates two core design choices of Universal Video Restorer: **frame-exact deterministic segmentation** and **resume-first recovery from late-stage failures**.
