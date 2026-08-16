# Changelog

## 1.0.0 — first public release

Public baseline derived from internal build `V1.6.3.2`.

Highlights:

- unattended folder mapping and confirmation workflow;
- checkpoint/resume architecture;
- smart per-file decode routing between NVIDIA NVDEC/CUDA, Intel QSV and CPU fallback;
- NVIDIA NVENC preferred for final encoding when available;
- PRE-VFR and POST-CFR benchmark stages using warm-up and repeated measurements/median;
- `BENCHMARK_GPU.csv` telemetry;
- exact frame census using FFprobe;
- VFR-to-CFR normalization;
- baked-in pillarbox detection and frame-level transition refinement;
- `libvidstab` stabilization;
- 1920x1080 composition with blurred fill for non-16:9 material;
- light audio denoise and two-pass loudness normalization;
- Unicode-safe concat handling;
- final mux without `-shortest`, preventing audio duration from cutting the final video frame;
- validation of very short audio/output files without a fixed 64 KB threshold;
- strict final frame-count validation and smoke-decode;
- historical metadata/source tracking with explicit provenance;
- metadata-only stream-copy maintenance mode;
- safe fast-resume of already validated final masters;
- project released under the MIT License to permit forks, modification and redistribution.

### Preservation policy at 1.0.0

Temporal metadata is evidence, not assumed ground truth. Embedded dates, filesystem timestamps, filename sequence and folder context are retained/reportable with source and confidence. The project deliberately avoids silently correcting camera clocks or inferring a definitive recording time.

## Pre-1.0 development history

### Beta — internal V1.6.3.x

Introduced archive metadata/provenance handling, parser fixes, core metadata validation, metadata-only remux and final-master fast resume.

### Beta — internal V1.6.2

Removed `-shortest` from final mux after a real case where a slightly shorter AAC track produced a master with one video frame missing.

### Beta — internal V1.6.1

Replaced the fixed 64 KB output-validity rule after very short legitimate AAC files were incorrectly rejected.

### Beta — internal V1.6

Added smart dual-GPU benchmark selection, PRE-VFR source benchmarking, POST-CFR benchmarking, warm-up/repeated median measurements, benchmark CSV and per-process GPU telemetry.

### Beta — internal V1.5

First dual-GPU NVIDIA/Intel QSV implementation.

### Alpha — internal V1.4

Added exact decoded-frame census and strict timeline/frame validation.

### Alpha — internal V1.3

Separated GPU encode capability from GPU decode capability and introduced per-file decode fallback.

### Alpha — internal V1.2

Early consolidated Universal Restorer with autonomous batch processing and checkpoints.

See `docs/VERSIONING.md` for the public/internal version mapping.
