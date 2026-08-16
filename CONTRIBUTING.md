# Contributing

Thanks for considering a contribution to Universal Video Restorer.

The project is intentionally conservative: preserving a usable, traceable master is more important than maximizing visual enhancement.

## Before changing code

Please open an Issue describing the problem or improvement. For processing bugs, include as much of the following as possible without sharing private media:

- public restorer version;
- Windows version;
- PowerShell version;
- FFmpeg build/version;
- GPU(s);
- source container/codec;
- resolution;
- CFR/VFR status;
- expected and observed frame count;
- selected CUDA/QSV/CPU route;
- relevant log excerpt;
- whether the problem reproduces with a short non-sensitive/synthetic sample.

## Preservation rules

Changes should not silently:

- overwrite originals;
- delete valid checkpoints;
- alter historical metadata semantics;
- infer a definitive capture time from weak evidence;
- stretch source geometry;
- remove frames to match audio duration;
- trade deterministic behavior for an opaque enhancement step.

If a proposal intentionally changes one of these policies, explain why and provide a migration path.

## Pull requests

Keep PRs focused. Describe:

1. the observed problem;
2. the proposed behavior;
3. files/codecs used to test it;
4. frame-count impact;
5. metadata/provenance impact;
6. CPU/GPU route impact;
7. resume/backward-compatibility impact.

Do not upload private family media to the repository. Prefer synthetic fixtures or public-domain/non-sensitive samples.

## Versioning

Public releases follow semantic versioning. Historical internal builds are documented as alpha/beta development lineage; do not renumber or rewrite them.

## License note

The repository does not yet declare an open-source license. Contributions/forking policy should be revisited when a license is selected.
