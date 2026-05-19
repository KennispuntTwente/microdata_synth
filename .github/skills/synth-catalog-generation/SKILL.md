---
name: synth-catalog-generation
description: Extend or debug metadata-driven synthetic generation based on catalog SQLite metadata, including data types, JSON metadata fields, code lists, period parsing, and search mode behavior (auto/fuzzy/fts). Use for changes in catalog queries, variable parsing, generation heuristics, and search dispatch.
---

# Catalog-Driven Generation Skill

## When To Use

Activate this skill when a user asks to:
- change how metadata fields drive value generation
- troubleshoot missing/incorrect variable metadata
- add support for new data type formats
- adjust search behavior between fuzzy and FTS
- improve generation realism while preserving constraints

## Key Files

- `R/catalog_interface.R`
- `R/data_generator.R`
- `R/main.R`
- `R/export.R`
- `tests/testthat/test-catalog-interface.R`
- `tests/testthat/test-main-search.R`
- `tests/testthat/test-export.R`

## Metadata Contract

`get_dataset_metadata()` should provide per-variable entries with:
- `name`
- `description`
- `data_type`
- `is_key`
- `key_type`
- `usage_notes` (from metadata JSON)
- `code_list` (from metadata JSON)
- `meta_length` (from metadata JSON)

Generation priority for values:
1. `code_list` values when present
2. parsed/normalized `data_type`
3. semantic fallbacks from variable name + description + usage notes

## Search Behavior

Use wrapper:
- `search_datasets(pattern, mode = "auto" | "fuzzy" | "fts", limit = N)`

Rules:
- `fuzzy`: in-memory substring search from `list_datasets()`
- `fts`: SQLite `datasets_fts MATCH` query
- `auto`: try FTS, fallback to fuzzy on error or no rows

If changing behavior, keep these mode semantics stable.

## Typical Change Pattern

### 1. Add/adjust parsing rule

Examples:
- new type pattern in `.parse_data_type()`
- improved date-like detection in `.looks_like_date_variable()`
- updated period parsing in `.parse_dataset_period()`

### 2. Add focused tests

Add regression tests in testthat files that:
- use deterministic seed
- avoid dependency on external catalog DB (use fixture/mocks)
- assert output columns and value constraints

### 3. Validate reporting alignment

When generation logic changes, validate impact on:
- `validate_data()` expectations
- dictionary and summary outputs
- NA-category behavior in reports

## Guardrails

- Keep query matching case-insensitive for dataset/key names.
- Preserve output column names and list/tibble structure.
- Do not silently remove existing fallback behavior.
- Ensure NA is treated as a category in reporting outputs.

## Verification Checklist

- `Rscript tests/testthat.R` passes.
- Search mode tests pass in `tests/testthat/test-main-search.R`.
- Catalog fixture tests pass in `tests/testthat/test-catalog-interface.R`.
- Export/report tests pass in `tests/testthat/test-export.R`.
