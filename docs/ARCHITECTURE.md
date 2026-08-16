# Architecture

## Processing pipeline

The 1.0.0 baseline follows this high-level sequence:

1. discover candidate media files and validate them with FFprobe;
2. map the entire batch before processing;
3. benchmark decode routes when relevant;
4. normalize VFR sources to CFR;
5. count frames actually decoded with FFprobe;
6. scan for baked-in pillarbox;
7. refine pillarbox transitions at native frame boundaries;
8. build an exact frame-number timeline;
9. run `libvidstab` detection and render each segment;
10. compose the 1920x1080 master;
11. concatenate video segments by stream-copy;
12. measure/process audio;
13. mux final video + audio without `-shortest`;
14. validate resolution, frame count, metadata and smoke-decode;
15. persist checkpoints/reports for resume.

## Core design decisions

### Exact frames over nominal duration

Legacy/VFR sources can report duration/FPS combinations that do not perfectly describe delivered frames. The restorer therefore uses an exact decoded-frame census and validates the final master against that count.

### Video-authoritative final mux

The final mux intentionally does not use `-shortest`. A real regression showed that an AAC stream ending a fraction earlier could make FFmpeg drop the final video frame. The complete rendered video timeline is authoritative.

### Hardware is optional, not trusted blindly

NVIDIA/Intel acceleration is selected per file. The pipeline prefers a measured route rather than assuming a GPU can decode every legacy codec simply because NVENC/QSV exists.

Current strategy includes:

- NVIDIA NVDEC/CUDA trial;
- Intel QSV trial where a matching decoder exists;
- warm-up + repeated measured runs;
- median comparison;
- CPU fallback;
- NVENC preferred for encode when available.

### CPU filters remain first-class

`libvidstab`, crop detection, complex blur/composition and analysis stages can remain CPU-bound even in a GPU-enabled pipeline. The project does not attempt zero-copy GPU processing at the expense of reliability.

### Unicode-safe concat

FFmpeg concat list files use relative paths. This avoids corrupting Unicode parent-directory names when the concat text itself must remain simple/portable.

### Checkpoints are part of the format

The `_WORK` directory is not merely scratch space. Validated `.done` files and intermediate masters allow long jobs to resume after interruption without unnecessary generational re-encoding.

Checkpoint identifiers that include internal development numbering are intentionally retained in public 1.0.0 for compatibility with pre-public batches.

### Wrapper status is not enough

A missing process exit code should not automatically invalidate a completed FFmpeg stage. Important stages cross-check `progress=end`, expected output presence, FFprobe readability and downstream validation.

## Output strategy

The pipeline produces H.264 1920x1080 masters designed for later family-film compilation rather than final distribution compression.

For sources whose active picture does not fill 16:9, the original foreground is preserved and a blurred fill is used rather than destructive stretching.

For baked-in pillarbox, black bars can be removed before stabilization/composition.

## Audio

The baseline architecture performs:

- optional light `afftdn` noise reduction;
- loudness measurement;
- corrected second pass;
- AAC output at 48 kHz.

Very short valid audio is accepted based on structural/FFprobe validation rather than an arbitrary 64 KB minimum.

## Public 1.0 compatibility constraints

When modifying the script, preserve these constraints unless a PR explicitly documents a migration:

- use `-/filter_complex <file>` on the reference FFmpeg build, not `-filter_complex_script`;
- avoid a PowerShell parameter named `[string[]]$Args` because of `$args`;
- avoid unsafe `$variable:` interpolation in bootstrap-compatible code;
- preserve PowerShell 7.6.4+ bootstrap/relaunch behavior;
- preserve exact frame validation;
- preserve resume/checkpoint semantics;
- do not reintroduce final `-shortest`.
