# microdata_synth - Copilot Instructions

## What This Project Is

An R-based synthetic CBS microdata generator that uses the microdata_catalogus SQLite metadata database.

It can:
- discover dataset schemas and key columns from catalog metadata
- generate synthetic values from data types and metadata JSON code lists
- generate linked datasets with referential integrity
- export CSV/RDS with dictionaries and summary reports

## Project Structure

```
R/
  main.R                   Entry point and public API
  catalog_interface.R      Catalog SQLite queries + metadata JSON parsing
  data_generator.R         Core generation and dataset linking logic
  validation.R             Type and referential integrity checks
  export.R                 CSV/RDS export and reporting helpers

examples.R                 End-to-end usage examples
multi_key_examples.R       Multi-key linking examples
LINKING_KEYS.md            Key-type notes and linking behavior
output/                    Generated example outputs
tests/testthat/            Test suite
```

## External Dependency

Expected catalog database path:
- `../microdata_catalogus/data/sqlite/catalogus.db`

If missing, functions that query metadata will fail with a clear error from `.get_catalogus_conn()`.

## R Environment

- R 4.4.1+
- Packages used by main scripts:
  - dplyr, purrr, stringr, readr
  - DBI, RSQLite
  - cli, glue, tibble, rlang, jsonlite

## Main Public API

Catalog exploration:
- `list_datasets()`
- `search_datasets(pattern, mode = c("auto", "fuzzy", "fts"), limit = 10)`
- `explore_catalogus()`
- `explore_join_keys()`
- `find_linkable_datasets(key_name = "RINPERSOON", key_type = NULL)`
- `find_datasets_by_key_type(key_type)`
- `get_dataset_metadata(dataset_name)`
- `get_dataset_keys(dataset_name)`

Generation:
- `generate_synthetic_data(dataset_name, n_records = 100, seed = NULL, key_ids = NULL)`
- `generate_linked_datasets(dataset_names, n_records = 100, seed = NULL, primary_dataset = NULL, link_by = NULL)`
- `generate_quick(dataset_name = "GBAPERSOONTAB", n_records = 100, output_dir = "./output")`
- `generate_suite(datasets, primary_n = 100, output_dir = "./output", format = c("csv", "rds"), validate = TRUE, verbose = TRUE)`

Validation and export:
- `validate_data(data, metadata)`
- `check_referential_integrity(datasets, primary_dataset = NULL, key_cols = NULL, verbose = TRUE)`
- `export_data(data, output_dir, dataset_name = NULL, format = c("csv", "rds"), overwrite = TRUE)`
- `export_datasets(datasets, output_dir, format = c("csv", "rds"), organize_by_dataset = FALSE, verbose = TRUE)`
- `create_data_dictionary(data, metadata = NULL, output_file = NULL)`
- `summary_statistics(data, output_file = NULL)`

## Search Modes

`search_datasets()` supports three backends:
- `mode = "fuzzy"`: in-memory case-insensitive substring filter on `list_datasets()`
- `mode = "fts"`: SQLite FTS query using `datasets_fts MATCH`
- `mode = "auto"`: try FTS first, then fallback to fuzzy if FTS errors or returns no rows

Implementation split:
- `search_datasets_fuzzy()` in `R/main.R`
- `search_datasets_fts()` in `R/catalog_interface.R`
- wrapper `search_datasets()` in `R/main.R`

## Key Behaviors

### Metadata-driven generation
- If variable metadata has `code_list`, values are sampled from that list directly.
- Metadata `length` overrides parsed SQL type length where present.
- Date-like columns can be inferred from name/description/usage notes.

### Period-aware date constraints
- Dataset `period` is parsed into start/end date bounds.
- Generated date values are clamped to period bounds.
- Start/end date pairs are enforced (`AANVANG/AANV/BEGIN/START/OPNAME` vs `EINDE/EIND`).

### Linking and integrity
- Linking is case-insensitive for key-name matching.
- Composite keys are sampled row-wise from the primary dataset.
- Referential integrity checks include mandatory tuple-level checks when 2+ shared keys exist.

### NA policy in reports
- In `create_data_dictionary()` and `summary_statistics()`, NA is treated as a category for uniqueness and character summaries.

## Testing

Run all tests:

```r
Rscript tests/testthat.R
```

Current tests cover:
- catalog-interface queries using a temporary SQLite fixture
- single and linked dataset generation behavior
- tuple-level referential integrity checks
- export/load paths and reporting edge cases
- search mode dispatch and fallback behavior

## Copilot Skills

Repository skills are available under `.github/skills/`:

- `synth-linking-integrity`
  - Focus: composite key propagation, tuple-level integrity, orphan diagnosis, linking regressions.
  - Entry file: `.github/skills/synth-linking-integrity/SKILL.md`

- `synth-catalog-generation`
  - Focus: metadata-driven generation, type/period parsing, fuzzy vs FTS search behavior, reporting alignment.
  - Entry file: `.github/skills/synth-catalog-generation/SKILL.md`

- `synth-test-authoring`
  - Focus: deterministic testthat authoring, fixtures/mocks, regression tests, and NA-category/report integrity assertions.
  - Entry file: `.github/skills/synth-test-authoring/SKILL.md`

- `synth-docs-examples-sync`
  - Focus: keeping README and example scripts aligned with actual API signatures and behavior.
  - Entry file: `.github/skills/synth-docs-examples-sync/SKILL.md`

## Editing Guidance

- Keep function outputs stable (tibble/list columns and names) because tests assert these.
- Preserve case-insensitive behavior for dataset/key lookups.
- When changing linking logic, keep composite tuple integrity and tuple-level validation aligned.
- When changing summary logic, keep NA treated as a valid category unless explicitly changed by project maintainers.
