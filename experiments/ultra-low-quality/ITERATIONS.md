# Ultra-low-quality restoration — iteration log

This branch isolates restoration experiments for extremely degraded sources. The goal is to promote only adaptive, evidence-based behavior back into the main restorer.

## R1 observation

The first conservative pipeline improved most 160x112 sources, but motion-compensated interpolation could create severe local warping during camera movement.

## Internal iterations before R2

1. **R1 baseline** — 2x pre-upscale + MCI/AOBMC, 8x8 blocks, VSBMC enabled. Good on stable scenes, but severe local deformation during camera motion.
2. **Native-resolution MCI** — interpolation before pre-upscale with coarser motion blocks. Faster, but residual deformation remained.
3. **Coarser MCI after 2x pre-upscale** — OBMC, 16x16 blocks, no VSBMC. Best always-on compromise: materially less deformation and lower processing cost than R1.
4. **Non-motion-vector frame-rate interpolation** — removed local warping but produced visible ghosting during motion.
5. **No synthetic motion** — cleanup/upscale only, preserving stored cadence. Best factual integrity during pans, but judder remained.
6. **Adaptive hybrid** — use conservative MCI in reliable windows and no-synthetic-frame fallback only in windows where the diagnostic indicates high interpolation risk. Best observed compromise.

## R2 hypothesis

Interpolation should be treated as an adaptive capability, not as a property of a camera or resolution class.

A window enters the safe fallback when diagnostic evidence indicates low reliability, using signals such as:

- detector disagreement;
- no-field / tracking availability;
- high jerk combined with implausible rotation.

Reliable windows may use conservative MCI. High-risk windows preserve the source cadence after cleanup, avoiding invented local motion.

Speed remains part of acceptance criteria. The adaptive gate should also reduce cost by avoiding expensive motion interpolation where it is least trustworthy.

## R2 blind A/B outcome — 2026-08-22

The second bench explicitly separated spatial cleanup from cadence reconstruction on the `Albino toca o barco` ULQ calibration clip.

Blind result: **AB03-A was preferred overall**. After unblinding, AB03-A corresponds to `v3_cleanup_strong`, a spatial-cleanup path that preserves the stored cadence.

Key findings:

- `v3_cleanup_strong` materially improved denoise/compression cleanup without introducing the temporal failures seen in the synthetic-motion variants.
- MCI materially improved perceived anti-shake and intermediate frames in reliable regions, but damaged pans and abrupt camera motion with local warping / bad synthesized frames.
- Blend-style cadence reconstruction could appear smoother in transitions, but did not provide a sufficiently good stability/quality trade-off.
- Full pipelines that combined cleanup with current MCI remained poor because temporal artifacts dominated the result.
- Spatial cleanup and temporal reconstruction must therefore be evaluated and gated independently.

Decision after R2:

1. Treat `v3_cleanup_strong` as the current **experimental ULQ spatial baseline**.
2. Do not promote current MCI or blend variants as always-on cadence reconstruction.
3. Preserve source cadence when temporal confidence is low, especially during pans and abrupt movement.
4. Evaluate true stabilization / anti-shake separately from synthetic-frame generation.
5. Start the next temporal bench from the spatial winner instead of from the failed MCI hybrids.

Full blind mapping, QA measurements and evaluation notes are recorded in `AB_R2_RESULTS.md`.
