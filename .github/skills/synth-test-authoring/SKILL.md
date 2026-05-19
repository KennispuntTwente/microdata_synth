---
name: synth-test-authoring
description: Create and maintain robust testthat tests for microdata_synth changes. Use for any feature, bug fix, or refactor that affects generation, linking, validation, export, catalog queries, or search behavior.
---

# Synthetic Test Authoring Skill

## When To Use

Activate this skill when a user asks to:
- add tests for a new feature
- add regression tests for a bug fix
- refactor code while preserving behavior
- improve test coverage for core functions

Use this skill by default for non-trivial code edits.

## Key Files

- `tests/testthat/helper-load.R`
- `tests/testthat/test-data-generator.R`
- `tests/testthat/test-validation.R`
- `tests/testthat/test-export.R`
- `tests/testthat/test-main-search.R`
- `tests/testthat/test-catalog-interface.R`
- `tests/testthat.R`

## Core Principles

1. Deterministic tests
- Use fixed seeds for generated data.
- Avoid assertions that depend on random ordering unless explicitly sorted.

2. Isolated dependencies
- Do not depend on external `../microdata_catalogus` in tests.
- Prefer temporary SQLite fixtures and mocked bindings.

3. Behavior-first assertions
- Assert function contracts: column names, row counts, keys, integrity flags, and summary values.
- Avoid brittle assertions tied to implementation internals.

4. Regression coverage
- Every bug fix should include at least one test that would fail before the fix.
- Name tests after user-visible behavior, not internal helper names.

5. Reporting consistency
- For dictionary/statistics outputs, keep NA as a category unless explicitly changed by maintainers.

## Test Patterns By Domain

### Generation and Linking

For `generate_synthetic_data()` and `generate_linked_datasets()`:
- Verify row/column structure.
- Verify code-list constrained variables only contain allowed values.
- Verify linked child keys originate from primary keys.
- For composite keys, verify tuple membership:

```r
parent_tuple <- paste(parent$RINPERSOON, parent$RINPERSOONS, sep = "|")
child_tuple  <- paste(child$RINPERSOON, child$RINPERSOONS, sep = "|")
expect_true(all(child_tuple %in% parent_tuple))
```

### Referential Integrity Validation

For `check_referential_integrity()`:
- Include per-column checks and tuple-level checks when 2+ keys are shared.
- Add explicit mismatch cases (for example swapped composite pairs).
- Assert integrity flags and orphan counts.

### Search Dispatch

For `search_datasets()`:
- Test `mode = "fuzzy"`, `mode = "fts"`, and `mode = "auto"`.
- In auto mode, test both FTS success and fallback behavior.
- Mock `search_datasets_fts()` and `search_datasets_fuzzy()` for precise dispatch tests.

### Export and Reporting

For `export_data()`, `export_datasets()`, `create_data_dictionary()`, `summary_statistics()`:
- Use temporary directories and verify output files exist.
- Verify round-trip loading for CSV and RDS.
- Assert NA-category behavior in uniqueness and top-frequency summaries.
- Include empty-data edge cases.

### Catalog Interface

For `list_datasets()`, `get_dataset_metadata()`, key discovery and stats:
- Use a temporary SQLite fixture with minimal schema and seed data.
- Verify metadata JSON parsing (`usage_notes`, `code_list`, `length`).
- Verify case-insensitive lookups for dataset and key names.

## Suggested Workflow

1. Identify changed behavior and affected module.
2. Add or update tests in the corresponding test file.
3. Add at least one regression test for the change.
4. Run full suite:

```r
Rscript tests/testthat.R
```

5. If failures are expected, update tests only when behavior change is intentional and documented.

## Completion Checklist

- Full suite passes with no failures.
- New behavior is covered by at least one test.
- Edge cases are covered where relevant.
- No external database dependency introduced.
- Test names clearly describe expected behavior.
