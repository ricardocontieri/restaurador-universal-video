# Ultra-low-quality restoration — A/B R2 results

Date: 2026-08-22

## Test source

Reference clip: `Albino toca o barco`, 160x112 MPEG-1 source used as the current ULQ calibration case.

The source is stored at nominal 25 fps but contains a strong repeated-frame pattern. The R2 bench intentionally separated spatial cleanup from cadence reconstruction so that user preference could be interpreted technically.

## Blind mapping after evaluation

- `AB01`: A = `v0_neutral` | B = `v1_cadence_mci`
- `AB02`: A = `v2_cadence_blend` | B = `v1_cadence_mci`
- `AB03`: A = `v3_cleanup_strong` | B = `v0_neutral`
- `AB04`: A = `v1_cadence_mci` | B = `v4_full_balanced`
- `AB05`: A = `v5_full_strong` | B = `v4_full_balanced`

## QA observations

All A/B outputs were normalized to the same presentation format: 1280x720, 25 fps, 837 frames, approximately 33.48 s.

Exact consecutive duplicate counts measured on the technical variants:

| Variant | Frames | Consecutive exact duplicates |
| --- | ---: | ---: |
| `v0_neutral` | 837 | 558 |
| `v1_cadence_mci` | 837 | 101 |
| `v2_cadence_blend` | 837 | 23 |
| `v3_cleanup_strong` | 837 | 558 |
| `v4_full_balanced` | 837 | 101 |
| `v5_full_strong` | 837 | 101 |

This confirms that `v3_cleanup_strong` changes spatial restoration while preserving the stored cadence, whereas the cadence-reconstruction variants materially alter the repeated-frame structure.

## Blind evaluation

### AB01 — neutral vs MCI cadence reconstruction

The neutral side preserved image quality better. MCI produced much better perceived stabilization and better intermediate frames outside pans, but became visibly poor during pans or abrupt camera movement.

**Interpretation:** MCI can improve perceived continuity in reliable motion, but is not acceptable as an always-on path because geometric errors become dominant during difficult camera motion.

### AB02 — blend cadence reconstruction vs MCI cadence reconstruction

MCI corrected several motion/stability issues, but compression artifacts remained and some synthesized frames were damaged during camera movement. The blend path had worse perceived stabilization but looked more fluid through transitions.

**Interpretation:** the two temporal approaches fail differently. MCI risks local warping; blend avoids some motion-vector deformation but trades it for weaker stability/blurred transition behavior. Neither is ready for promotion.

### AB03 — strong spatial cleanup vs neutral

`v3_cleanup_strong` was clearly preferred. Denoise was materially better, while the remainder appeared substantially equivalent. Anti-shake remained insufficient on both sides.

**Interpretation:** this is the cleanest positive result of R2. Spatial cleanup provides a visible benefit without depending on synthetic-frame reconstruction.

### AB04 — MCI cadence reconstruction vs balanced cleanup + MCI

Both sides were judged poor. Motion artifacts and degraded pans/transitions dominated the comparison and prevented meaningful evaluation of subtler spatial differences.

**Interpretation:** spatial cleanup cannot rescue an unreliable temporal reconstruction path. Temporal failure masks the value of other filters.

### AB05 — stronger full restoration vs balanced full restoration

The stronger path showed denoise approaching the AB03-A result, but both sides suffered from the same temporal problems seen in AB04.

**Interpretation:** stronger spatial cleanup may remain promising, but it must be compared again without MCI before any conclusion about its ideal strength.

## Current winner

**Best overall result: `AB03-A` = `v3_cleanup_strong`.**

This becomes the current ULQ spatial-cleanup reference for the Albino calibration case.

It does **not** solve the repeated-frame cadence or stabilization problem. Its value is that it improves compression/noise while preserving temporal factual integrity better than the synthetic-motion candidates tested in R2.

## Decisions

1. Promote `v3_cleanup_strong` to **experimental spatial baseline**, not yet to the main restorer.
2. Reject current MCI and blend variants as **always-on cadence reconstruction**.
3. Do not evaluate spatial strength through MCI-based hybrids; temporal artifacts dominate the result.
4. Separate three capabilities in subsequent testing:
   - spatial cleanup;
   - true camera stabilization / anti-shake;
   - repeated-frame cadence reconstruction / synthetic motion.
5. Temporal reconstruction must use a conservative fallback during pans, abrupt motion, low-confidence tracking, or other unreliable windows.
6. The next temporal round should start from the winning spatial baseline (`v3_cleanup_strong`) and preserve source cadence whenever interpolation confidence is low.

## Next experiment

The next bench should first refine spatial cleanup without synthetic frames, comparing the current winner against nearby strengths. In parallel, temporal work should test an adaptive gate that disables synthetic motion during pans and abrupt movement instead of forcing MCI across the whole clip.

Success criteria for temporal work:

- fewer perceptually disturbing repeated frames in safe windows;
- no severe local warping during pans;
- no damaged synthesized frames during abrupt motion;
- no ghosting that is more distracting than the original judder;
- measurable improvement in perceived stability without sacrificing geometric integrity.
