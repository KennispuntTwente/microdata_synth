---
name: synth-linking-integrity
description: Diagnose and fix linking bugs in synthetic CBS datasets, including composite key tuple mismatches, orphaned records, key-name case mismatches, and period/date ordering issues. Use for requests about generate_linked_datasets, check_referential_integrity, key propagation, tuple-level integrity, and cross-dataset linkage regressions.
---

# Synthetic Linking Integrity Skill

## When To Use

Activate this skill when a user asks to:
- debug broken links between generated datasets
- investigate orphaned foreign keys
- validate or enforce composite key behavior
- change key propagation in `generate_linked_datasets()`
- improve referential integrity checks in `check_referential_integrity()`

## Key Files

- `R/data_generator.R`
- `R/validation.R`
- `R/catalog_interface.R`
- `tests/testthat/test-data-generator.R`
- `tests/testthat/test-validation.R`

## Workflow

### 1. Confirm metadata key structure

- Use `get_dataset_metadata(dataset_name)` to inspect `is_key` and `key_type`.
- Compare key names case-insensitively.
- Verify whether the dataset uses single or composite keys.

### 2. Reproduce with minimal deterministic example

Use a fixed seed and very small record counts.

```r
source("R/main.R")

out <- generate_linked_datasets(
  dataset_names = c("SECMBUS", "SPOLISBUS"),
  primary_dataset = "SECMBUS",
  n_records = list(SECMBUS = 20, SPOLISBUS = 40),
  seed = 42
)

check_referential_integrity(out)
```

For composite keys, test tuple membership explicitly:

```r
parent <- out[["SECMBUS"]]
child  <- out[["SPOLISBUS"]]

parent_tuple <- paste(parent$RINPERSOON, parent$RINPERSOONS, sep = "|")
child_tuple  <- paste(child$RINPERSOON, child$RINPERSOONS, sep = "|")

sum(!child_tuple %in% parent_tuple)
```

### 3. Enforce tuple-safe sampling

When multiple link keys are shared:
- sample primary row indices once
- derive every linked key column from those same sampled rows
- do not sample each key column independently

### 4. Keep validation aligned with generation

If generation preserves tuples, validation must verify tuples.
For 2+ shared keys:
- include a tuple-level integrity row in reports
- keep per-column checks too, but do not rely on them alone

### 5. Check date constraints after linkage changes

Run date sanity checks because link rewrites can accidentally alter constraints:
- generated date values must stay within dataset period
- start/end pairs must satisfy start <= end

## Guardrails

- Preserve case-insensitive key matching behavior.
- Keep backward-compatible return shapes for integrity reports.
- Treat warnings about cross-sectional duplicates as signal, not hard errors.

## Verification Checklist

- `Rscript tests/testthat.R` passes.
- Composite tuple test passes in `tests/testthat/test-validation.R`.
- No new warnings in data generator tests.
- For target datasets, orphan count is zero when expected.
