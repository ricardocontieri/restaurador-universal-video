# Universal Video Restorer

[Português](README.pt-BR.md)

**Current stable release: 1.0.0**  
**Current release candidate: 1.0.1-RC3** (`release/1.0.1-rc3`)  
Internal stable lineage: `V1.6.3.2`

> RC3 is an A/B-calibrated candidate with more selective scene-aware stabilization, spatial tracking consensus, transition reacquisition and voice-safe audio. Stable `1.0.1` remains gated by the calibration blind test. See [RC3 release notes](docs/releases/1.0.1-rc3.md).

Universal Video Restorer is a Windows PowerShell + FFmpeg pipeline for restoring and normalizing personal or archival video collections into reusable 1080p masters while keeping technical and historical traceability.

The project grew out of real-world restoration of mixed family-video archives: MPEG-1, AVI/MJPEG, H.264, VFR material, short clips, old metadata, pillarboxed sources and interrupted long-running jobs. The goal is not to invent missing information or apply aggressive AI enhancement. It is to create repeatable, inspectable masters that can later be used in compilations.

## What it does

- maps and validates a folder before processing;
- normalizes VFR sources to CFR when needed;
- benchmarks NVIDIA NVDEC/CUDA and Intel Quick Sync/QSV per file;
- falls back to CPU when hardware decode is not suitable;
- performs exact decoded-frame census;
- detects baked-in pillarbox and refines transitions by frame;
- stabilizes with `libvidstab`;
- composes a 1920x1080 master with blurred background where appropriate;
- performs light audio cleanup and two-pass loudness normalization;
- resumes from checkpoints after interruption;
- validates final frame count and smoke-decodes the output;
- preserves and reports historical metadata with source/provenance instead of silently treating timestamps as ground truth.

## Requirements

Reference environment:

- Windows 10/11
- PowerShell 7.6.4+
- FFmpeg full build with `libvidstab`
- NVIDIA NVENC/NVDEC optional
- Intel Quick Sync/QSV optional

The public 1.0.0 baseline was exercised on FFmpeg 9.0 with an NVIDIA RTX 2050 and Intel Iris Xe. Other hardware/codecs may take different routes or fall back to CPU.

## Quick start

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\src\RestauradorUniversal.ps1
```

The script first maps the videos and asks for confirmation before starting autonomous processing. Originals are never overwritten.

Metadata-only maintenance of already-created masters:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\src\RestauradorUniversal.ps1 `
  -SomenteMetadados
```

## Preservation philosophy

Old camera clocks are not necessarily trustworthy. A filesystem timestamp, embedded camera date, filename sequence or folder year is evidence, not automatically the true recording time. The restorer preserves the source and confidence of temporal evidence so a future editor can reconstruct chronology without having earlier assumptions baked into the archive.

See [Forensic metadata policy](docs/FORENSIC_METADATA.md).

## Versioning

`1.0.0` is the first stable public release. `1.0.1-RC3` is the current release candidate and remains under blind calibration before promotion to stable `1.0.1`. All earlier internal iterations are classified as alpha/beta development builds and preserved under `legacy/`. Their original internal banners are intentionally left unchanged for provenance. See [VERSIONING.md](docs/VERSIONING.md).

## Contributing and forks

Forks, codec/hardware reports and improvements are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and open an Issue before changing core preservation behavior. A useful contribution includes the source codec/resolution/FPS, expected frame count, relevant log excerpt, hardware route and a reproducible failure description.

Do not upload private family media just to demonstrate a bug. Prefer synthetic or non-sensitive samples.

## Real-world case studies

The repository keeps sanitized regression records from real archival runs so fixes remain reproducible without publishing private media.

- [Unicode-safe concat after frame-exact segmented restoration](docs/case-studies/unicode-frame-exact-regression.md) — documents a late-stage concat failure caused by a Unicode parent path, the relative ASCII-path fix, checkpoint reuse, 173 timeline segments and successful 4/4 final validation.

## Project status

This is a practical restoration tool rather than a polished commercial product. The first public baseline reflects the pipeline that survived multiple real archival batches, including legacy VFR MPEG-1 and very short clips. There are still known areas for improvement; see [ROADMAP.md](docs/ROADMAP.md).

## License

Released under the [MIT License](LICENSE). You may use, modify, fork, redistribute and incorporate the project into other work under the terms of that license.
