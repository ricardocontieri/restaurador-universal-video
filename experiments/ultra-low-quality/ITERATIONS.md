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
