# Forensic metadata and provenance policy

## Purpose

The restorer prepares archival masters for future editing while retaining enough evidence to revisit chronology later.

For legacy consumer cameras, date/time information is often unreliable. Users could set the camera clock incorrectly, batteries could reset it, copied files could acquire new filesystem timestamps, and old containers may expose little or no embedded metadata.

The governing rule is therefore:

> **Preserve first; interpret later.**

## Evidence is not truth

The following may all be useful historical evidence, but none is automatically treated as the true recording time:

- container-level date/time tags;
- video/audio stream tags;
- original file `CreationTimeUtc`;
- original file `LastWriteTimeUtc`;
- filename/sequence number;
- relative directory and archive context;
- a year present in the path;
- visual/content clues evaluated later.

A timestamp selected for cataloguing or compatibility must keep its **source**, **meaning** and **confidence** visible.

Example:

```text
HistoricalTimestamp = 2007-08-04T17:37:16Z
TimestampSource = Filesystem:LastWriteTimeUtc
TimestampMeaning = source-preserved historical timestamp
TimestampConfidence = medium
```

This does **not** mean “the camera definitely recorded the scene at this instant.”

## Current 1.0.0 behavior

Public 1.0.0 inherits the archive-date implementation developed internally in V1.6.3.2.

The pipeline:

1. searches embedded date/time-like tags exposed by FFprobe;
2. records filesystem creation/write timestamps from the original file;
3. uses year hints from the path only as a plausibility check, never as a fabricated date;
4. records the selected timestamp source and confidence;
5. produces `METADADOS_DATAS.csv` with the observed candidates and warnings;
6. can maintain metadata by stream-copy with `-SomenteMetadados`.

For compatibility with common media tools, a selected historical timestamp can be written to MP4 `creation_time`. Its provenance must still be preserved in the report. This field should not be interpreted as stronger evidence than its source permits.

## What the restorer must not do silently

- convert a directory year into January 1st of that year;
- adjust timestamps to a guessed local timezone and discard the original value;
- call `LastWriteTime` a definitive `capture_time`;
- overwrite a stronger embedded timestamp with a weaker inferred one;
- hide conflicting dates;
- remove the original filename/path relationship from reports;
- destroy source files after creating masters.

## Filesystem timestamps

The original filesystem timestamps are evidence about the archived source file. They may reflect capture, transfer, copy, edit or migration activity.

Public 1.0.0 can mirror source filesystem timestamps onto the output master for continuity, while also recording restoration time separately. This is a convenience/preservation behavior, not an assertion about capture time.

Use `-SemPreservarDatasSistemaArquivos` when this mirroring is undesirable.

## Future provenance manifest

A planned evolution is a per-file provenance manifest containing, at minimum:

```text
OriginalFileName
OriginalRelativePath
OriginalSHA256
OriginalContainerMetadata
OriginalStreamMetadata
OriginalCreationTimeUtc
OriginalLastWriteTimeUtc
HistoricalTimestampSelected
HistoricalTimestampSource
HistoricalTimestampConfidence
RestoredFileName
RestoredSHA256
RestorationTimeUtc
RestorerPublicVersion
RestorerInternalLineage
FFmpegVersion
ProcessingRoute
OriginalFrameCount
FinalFrameCount
```

Hashes would bind a restored master to the exact source bytes without requiring the media itself to be published.

## Contribution rule

Any pull request that changes timestamp selection, metadata writing or provenance semantics should explain whether it changes:

- evidence collection;
- interpretation/ranking;
- output compatibility metadata;
- filesystem timestamps;
- reports/manifests.

Behavior-changing metadata PRs should include a migration note so existing archives are not silently reinterpreted.
