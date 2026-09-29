# Fidelity Backlog

Known limitations and possible improvements for this experimental generator. These items
are ideas, not commitments or guarantees of future behavior.

## Why this file exists

Synthetic output is useful for development and tests, but it does not reproduce every
property of real microdata. Passing checks on generated data is not evidence that a workflow
is correct for real data.

## Items

### 1. No realistic per-person period history

**Status:** tier 2 (workaround in place)

The generator produces **independent dates per row** — it enforces only `start <= end`
within a row. It does not produce a coherent history *per person*: adjacent,
non-overlapping intervals that tile a person's timeline the way real registry data does.

Anything exercising interval logic (interval joins, gaps-and-islands, rollups over periods)
therefore gets unrepresentative input from synth as it stands.

**Current limitation:** consumers that need realistic histories must construct those
fixtures themselves.

**Possible improvement:** add optional per-person interval generation so period-aware
fixtures can be produced by the generator.

### 2. Export format is CSV/RDS, not parquet

**Status:** tier 2 (workaround in place)

Synth exports CSV and RDS. The real pipeline works in parquet throughout, so every consumer
converts. Consumers currently do this with `arrow` after the fact.

**The improvement:** optional parquet output. Small, and it removes a conversion step plus a
class of dtype-drift surprises between what synth emits and what the pipeline reads.

### 3. Real-data quirks are absent

**Status:** known limitation

Synth generates well-formed values. Real microdata is not well-formed: geography can be
missing, `RINPERSOON` values can be odd, and the scale is far larger. Code that passes on
synth can still fail on the real thing, which means passing on synth is
*necessary but not sufficient* as a validation gate.

Synthetic data cannot be assumed to contain every irregularity found in real data. Better
coverage may help identify issues earlier, but validation with synthetic data cannot replace
testing and review in the intended environment.

### 4. Static attributes can disagree across linked tables

**Status:** known limitation

Linked datasets share person keys, but non-key attributes are generated independently.
The same `RINPERSOON` can therefore have different values for `GESLACHT` or
`GBAGEBOORTEJAAR` in different tables, even though those attributes should be stable.
Key-level referential integrity checks do not detect this discrepancy.

**Possible improvement:** optionally reuse stable entity attributes across datasets during
linked generation.

### 5. Inline code lists in descriptions are not used as a fallback

**Status:** structured `code_list` is supported; description parsing is not

When catalog metadata contains a `code_list`, synth samples its codes. If the list is
missing but the variable description says, for example, `1 = Man, 2 = Vrouw`, the
generator falls back to generic values instead of those documented codes.

**Possible improvement:** parse unambiguous code-label pairs from descriptions only when
structured codes are absent, and reject uncertain matches.

### 6. Secondary entity IDs are not shared across a generated suite

**Status:** explicit linking via primary keys is available; shared secondary ID pools are not

`generate_linked_datasets()` shares keys from the selected primary dataset. Other entity
keys introduced by a secondary table are generated anew, so further tables cannot draw
from the same pool without explicitly supplying IDs.

**Possible improvement:** allow a suite to reuse typed entity IDs for secondary relationships
while preserving row-level composite key integrity. Merely sampling from the same pool
does not by itself establish a valid relationship between records.

## Adding to this file

Record the gap, why it matters, whether a workaround exists, and what the improvement would
be. Err towards writing it down: the point of this file is that no improvement idea gets
dropped merely because it fell outside the project that noticed it.
