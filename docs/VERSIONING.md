# Versioning

## Public version line

The public project starts at **1.0.0**.

Public `1.0.0` is derived directly from the internal development build **V1.6.3.2**. The public renumbering does not imply that six previous public major versions existed; those numbers were internal development identifiers created while the pipeline was being tested against real archival batches.

The current source banner identifies public `1.0.0`, while selected historical scripts retain their original internal banners and filenames.

## Pre-1.0 development lineage

The historical line is classified for public documentation as follows:

| Public classification | Internal build | Main milestone |
|---|---:|---|
| alpha | V1.2 | Early universal unattended pipeline with checkpoints |
| alpha | V1.3 | Separate GPU encode/decode capability and per-file decode fallback |
| alpha | V1.4 | Exact decoded-frame census and strict frame validation |
| beta | V1.5 | NVIDIA + Intel QSV dual-GPU routing |
| beta | V1.6 | Smart pre/post-VFR benchmarking, median measurements, GPU telemetry and benchmark CSV |
| beta | V1.6.1 | Short-output/audio validation fix |
| beta | V1.6.2 | Video-authoritative final mux; removal of `-shortest` |
| beta | V1.6.3 | Archive-date/provenance work begins |
| beta | V1.6.3.1 | PowerShell parser correction |
| beta | V1.6.3.2 | Archive metadata validation refinement and safe final resume |
| stable | **1.0.0** | First public baseline; code lineage V1.6.3.2 |

Not every internal build survives as a separate source file in this repository. Available historical source snapshots are stored under `legacy/`; missing intermediate snapshots are documented here rather than reconstructed or fabricated.

## Why preserve internal identifiers?

Some checkpoint filenames and metadata schema identifiers contain internal version strings such as `V163`. They remain in public 1.0.0 because changing them only for cosmetic versioning could break resume compatibility with batches already processed during development.

Future public releases should use semantic versioning (`MAJOR.MINOR.PATCH`) and avoid exposing internal development numbering in user-facing banners.

## Compatibility principle

A public version bump should not silently invalidate existing work directories. If a future change requires incompatible checkpoints or metadata schemas, document the migration explicitly and prefer a safe validation/rebuild path over automatic deletion.
