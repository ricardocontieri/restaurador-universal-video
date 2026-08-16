# Roadmap

The roadmap favors archival reliability and reproducibility over aggressive restoration features.

## High priority

- provenance manifest per source/master pair;
- SHA-256 of original and restored master;
- explicit terminology separating historical timestamps from asserted capture time;
- PowerShell parser/static checks in CI;
- regression fixtures for very short clips/audio;
- regression fixture for the final-frame/`-shortest` case;
- Unicode path/concat regression tests;
- VFR frame-count regression tests;
- metadata cases with no embedded timestamp and old filesystem timestamps;
- document/test clean installation of PowerShell + FFmpeg dependencies.

## Medium priority

- clearer Intel QSV telemetry and vendor attribution;
- broaden original-source hardware benchmark coverage for legacy codecs;
- rotation metadata handling;
- interlace detection/deinterlace policy;
- consolidated quality/provenance report;
- optional sidecar JSON manifest suitable for future compilation tooling;
- sanitized sample media or generated fixtures that can be published with the project.

## Lower priority

- simpler front-end/launcher;
- packaging/installer;
- optional presets for archival master vs viewing copy;
- additional platforms after the Windows reference implementation becomes testable.

## Contribution candidates

Good first contributions include:

- reproducible codec compatibility reports;
- CI/parser validation;
- documentation improvements;
- synthetic test fixtures;
- non-destructive metadata/provenance improvements;
- performance measurements on different NVIDIA/Intel hardware.

Before proposing a processing-quality change, describe whether it is intended to improve preservation, compatibility, performance or appearance. Appearance-only changes should remain optional whenever possible.
