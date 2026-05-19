# microdata_synth — Synthetic CBS Microdata Generator

Generate realistic synthetic CBS (Statistics Netherlands) microdata from the official catalog metadata.

## Overview

This project uses the [microdata_catalogus](https://github.com/KennispuntTwente/microdata_catalogus) SQLite database to:

- discover dataset structures and variable definitions
- generate synthetic values that respect metadata constraints
- produce linked datasets with referential integrity

The generator now supports:

- all 7 key types (person, business, job, household, object, address, education)
- composite key-aware linking (for example `RINPERSOON + RINPERSOONS` sampled as a pair)
- metadata JSON integration (`code_list`, `usage_notes`, `length`)
- case-insensitive dataset and key matching
- period-aware date generation and start/end ordering constraints

## Quick Start

### 1. Install dependencies

```r
renv::restore()
```

### 2. Load the generator

```r
source("R/main.R")
```

### 3. Explore and generate

```r
# Fuzzy search
search_datasets("polis")

# Explore catalog and keys
explore_catalogus()
explore_join_keys()

# Generate one dataset
secm <- generate_synthetic_data("SECMBUS", n_records = 500, seed = 42)

# Generate linked datasets
linked <- generate_linked_datasets(
  dataset_names = c("SECMBUS", "SPOLISBUS"),
  primary_dataset = "SECMBUS",
  n_records = list(SECMBUS = 500, SPOLISBUS = 1000),
  seed = 42
)

# Validate and export
check_referential_integrity(linked)
export_datasets(linked, output_dir = "output/sociaal_vangnet", format = "csv")
```

### 4. One-command workflow

```r
generate_suite(
  datasets = c("SECMBUS", "SPOLISBUS"),
  primary_n = 500,
  output_dir = "output/sociaal_vangnet",
  format = c("csv", "rds"),
  validate = TRUE,
  verbose = TRUE
)
```

## Current Project Structure

```
R/
├── main.R                   # Entry point and public API
├── catalog_interface.R      # SQLite catalog queries + metadata JSON parsing
├── data_generator.R         # Core generation and constraint logic
├── validation.R             # Type/range/integrity validation
└── export.R                 # CSV/RDS export helpers

output/                      # Generated datasets
renv/                        # Reproducible R environment
```

## Key Behaviors and Constraints

### Metadata-driven generation

- `code_list` values are used directly when available
- `usage_notes` and descriptions are used for semantic detection (for example date fields)
- explicit metadata `length` overrides parsed SQL type lengths

### Key handling

- linking is case-insensitive
- composite keys stay row-consistent when linking datasets
- `RINPERSOONS` is generated from metadata code lists (one-letter source code), not numeric IDs

### Date handling

- dataset `period` is parsed and used as generation bounds
- start/end pairs are enforced with synonym-aware matching:
  - start patterns: `AANVANG`, `AANV`, `BEGIN`, `START`, `OPNAME`
  - end patterns: `EINDE`, `EIND`
- only valid parseable date rows are adjusted (to avoid sentinel-code corruption)

### Validation improvements

- empty metadata `data_type` values are handled gracefully
- `num(N)` and `int(N)` specifications are parsed correctly
- referential integrity reporting works for composite person keys

## Main API

Catalog exploration:
- `list_datasets()`
- `list_variables(dataset_name)`
- `search_datasets(pattern, mode = c("auto", "fuzzy", "fts"), limit = 10)`
- `search_datasets_fuzzy(pattern, limit = 10)`
- `search_datasets_fts(keyword, limit = 10)`
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
- `validate_data(data, metadata, verbose = TRUE)`
- `check_referential_integrity(datasets, primary_dataset = NULL, key_cols = NULL, verbose = TRUE)`
- `check_duplicates(data, by = NULL)`
- `data_quality_report(data, metadata = NULL)`
- `export_data(data, output_dir, dataset_name = NULL, format = c("csv", "rds"), overwrite = TRUE)`
- `export_datasets(datasets, output_dir, format = c("csv", "rds"), organize_by_dataset = FALSE, verbose = TRUE)`
- `load_data(filepath, format = NULL)`
- `create_data_dictionary(data, metadata = NULL, output_file = NULL)`
- `summary_statistics(data, output_file = NULL)`

## Requirements

- R 4.4.1+
- `microdata_catalogus` SQLite database at `../microdata_catalogus/data/sqlite/catalogus.db`
- Required packages (auto-checked in `R/main.R`):
  - `dplyr`, `purrr`, `stringr`, `readr`
  - `DBI`, `RSQLite`
  - `cli`, `glue`, `tibble`, `rlang`, `jsonlite`

## Notes

- This repository generates synthetic data only; it does not expose real CBS microdata.
- Output realism depends on metadata quality in the catalogus.

## Copilot Documentation

- Repository-specific Copilot feature and behavior documentation:
  - `.github/copilot-instructions.md`
- Repository Copilot skills:
  - `.github/skills/synth-linking-integrity/SKILL.md`
  - `.github/skills/synth-catalog-generation/SKILL.md`
  - `.github/skills/synth-test-authoring/SKILL.md`
  - `.github/skills/synth-docs-examples-sync/SKILL.md`

## License

MIT
