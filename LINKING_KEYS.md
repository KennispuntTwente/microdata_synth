# Linking Variables & Multi-Key Data Generation

## Overview

CBS microdata supports **7 types of linking keys** beyond just person IDs (RINPERSOON). The updated generator can now automatically detect and handle all of them.

## Key Types Available

| Type | Example Keys | # Datasets | Use Case |
|------|--------------|-----------|----------|
| **Person** | RINPERSOON, RINPERSOONS | 303 | Link all person-based datasets |
| **Business** | BEID | 15 | Link business/employment datasets |
| **Job** | IKVID, BAANRUGID | 8-10 | Link employment records |
| **Household** | HUESSION, HUESSION2 | 5+ | Link household/family data |
| **Object/Dwelling** | RINOBJECT, VSLSLEUTELBUS | 3+ | Link address-based data |
| **Address** | ADRESRUGNR | 1+ | Link street/building data |
| **Education** | OGESSION | 1+ | Link education enrollment |

## Database Insights

From the microdata_catalogus database analysis:

- **626 total datasets** with **21,316 variables**
- **772 variables** marked as key/linking columns
- **19 known join keys** documented in the database
- **Case variations exist** (e.g., RINPERSOON, RINPersoon, Rinpersoon)

## New Functions

### Exploring Keys

```r
# See all available linking keys
explore_join_keys()

# Get keys used in a specific dataset
get_dataset_keys("PERSONEN")

# Find all datasets using a specific key
find_linkable_datasets("RINPERSOON")
find_linkable_datasets(key_type = "business")

# Find datasets by key type
find_datasets_by_key_type("job")
find_datasets_by_key_type("household")
```

### Generating with Auto-Detected Keys

```r
# Generate linked datasets - automatically detects all key columns
synthetic <- generate_linked_datasets(
  dataset_names = c("PERSONEN", "HUISHOUDENS", "INKOMSTEN"),
  n_records = 500
)

# The function will:
# 1. Find all key columns in PERSONEN
# 2. Generate synthetic IDs for each key type (person, household, etc.)
# 3. Use these IDs to link HUISHOUDENS and INKOMSTEN
# 4. Ensure referential integrity across all datasets
```

### Validating Multi-Key Integrity

```r
# Automatically validates all key columns
integrity <- check_referential_integrity(
  datasets = synthetic,
  primary_dataset = "PERSONEN"
)

# Output shows status for each key type:
# - RINPERSOON linking: ✓ OK
# - HUESSION linking: ✓ OK
# - etc.
```

### Advanced: Manual Key Specification

```r
# If you want to link by specific keys only
synthetic <- generate_linked_datasets(
  dataset_names = c("PERSONEN", "BEDRIJVEN"),
  n_records = 500,
  primary_dataset = "PERSONEN",
  link_by = c("RINPERSOON", "BEID")  # explicitly choose keys
)
```

## How It Works

### Key ID Generation

Each key type uses a different format/range:

```r
# Internally:
# Person IDs (RINPERSOON):  9-digit (100000000-999999999)
# Business IDs (BEID):      8-digit (10000000-99999999)
# Job IDs (IKVID):          12-digit (100000000000-999999999999)
# Household IDs (HUESSION): 9-digit (100000000-999999999)
# Object IDs (RINOBJECT):   9-digit (100000000-999999999)
# Address IDs (ADRESRUGNR): 10-digit (1000000000-9999999999)
# Education IDs (OGESSION): 12-digit (100000000000-999999999999)
```

### Automatic Key Detection

The generator:

1. **Reads metadata** from the catalogus database
2. **Identifies all key columns** in each dataset (via `is_key` flag and `key_type`)
3. **Generates appropriate IDs** based on the key type
4. **Links datasets** by matching keys
5. **Validates integrity** - ensures all foreign keys exist in primary keys

## Example: Multi-Dataset Linking

```r
source("R/main.R")

# See what keys are available
explore_join_keys()

# Find person-based datasets we can link
find_linkable_datasets("RINPERSOON")

# Generate 1000 people with multiple linked tables
# (auto-detects RINPERSOON, HUESSION, and other keys)
synthetic <- generate_linked_datasets(
  c("PERSONEN", "HUISHOUDENS", "INKOMSTEN"),
  n_records = list(
    PERSONEN = 1000,
    HUISHOUDENS = 400,
    INKOMSTEN = 2000
  )
)

# Check that all links are valid
check_referential_integrity(synthetic)

# Export all datasets
export_datasets(synthetic, "output/", format = c("csv", "rds"))

# Create data dictionary for each
for (ds_name in names(synthetic)) {
  meta <- get_dataset_metadata(ds_name)
  create_data_dictionary(
    synthetic[[ds_name]],
    metadata = meta,
    output_file = paste0("output/", ds_name, "_codebook.csv")
  )
}
```

## Finding Linkable Datasets

### Person-Based Linking (Most Common)

```r
# 303 datasets use RINPERSOON
person_datasets <- find_linkable_datasets("RINPERSOON")

# Can generate any combination:
generate_linked_datasets(
  c("PERSONEN", "HUISHOUDENS", "INKOMSTEN", "WERKNEMERS"),
  n_records = 500
)
```

### Business-Based Linking

```r
# 15 datasets use BEID
business_datasets <- find_linkable_datasets("BEID")

# Example: Polisbus (employee records) + other business data
synthetic <- generate_linked_datasets(
  c("PERSONEN", "BETAB", "EWLBUS"),
  n_records = 1000,
  link_by = "BEID"  # link via business ID
)
```

### Job-Based Linking

```r
# 8-10 datasets use IKVID (modern) or BAANRUGID (legacy)
job_datasets <- find_datasets_by_key_type("job")

# Employment history data
synthetic <- generate_linked_datasets(
  c("PERSONEN", "INCIJFERS", "BANEN"),
  n_records = 500,
  link_by = "IKVID"
)
```

## Case Sensitivity

⚠️ **Note**: The database contains case variations:
- `RINPERSOON`, `RINPersoon`, `Rinpersoon`, `rinpersoon`

The generator handles this, but be aware when working with raw data.

## Troubleshooting

### "No linking keys found"

```r
# Check if dataset has any key columns
get_dataset_keys("MYDATA")

# If empty, the dataset doesn't have linking keys
# You'll need to generate data independently
```

### "Found orphaned records"

```r
# Some child records don't link to parent
# This can happen if:
# 1. Primary dataset has fewer records than child
# 2. Child dataset uses different key type
# 3. Key column missing in one dataset

# Check integrity
check_referential_integrity(synthetic, verbose = TRUE)

# Regenerate with proper linking
synthetic <- generate_linked_datasets(
  c("PERSONEN", "CHILD_DATA"),
  n_records = list(PERSONEN = 1000, CHILD_DATA = 1000),
  link_by = "RINPERSOON"
)
```

### "Key column name mismatch"

If datasets use different names for the same key (e.g., `RINPERSOON` vs `RIN`):

```r
# Check both datasets
get_dataset_keys("DATASET1")
get_dataset_keys("DATASET2")

# Manually specify the linking column
synthetic <- generate_linked_datasets(
  c("DATASET1", "DATASET2"),
  link_by = "RINPERSOON"  # explicit key name
)
```

## Technical Details

### Database Schema

The catalogus tracks keys via:

```sql
-- join_keys table: known keys and their types
CREATE TABLE join_keys (
  key_name TEXT,        -- e.g. "RINPERSOON"
  key_type TEXT,        -- e.g. "person"
  description TEXT      -- semantic meaning
);

-- variables table: which columns are keys
CREATE TABLE variables (
  ...
  is_key INTEGER,       -- 1 if this is a key column
  key_type TEXT,        -- e.g. "person", "business"
  ...
);
```

### Auto-Detection Algorithm

```
For each dataset:
  1. Read all variables
  2. Filter to is_key = 1
  3. Group by key_type
  4. Generate IDs appropriate for that type
  5. Use generated IDs for linking
```

## Future Enhancements

Potential improvements:
- [ ] Support for composite keys (multiple columns)
- [ ] Cross-key linking (link via person + business)
- [ ] Key type constraints during validation
- [ ] Custom ID generation patterns
- [ ] Temporal linking (link by year/period)

## References

See `README.md` for general usage and `examples.R` for detailed examples.
