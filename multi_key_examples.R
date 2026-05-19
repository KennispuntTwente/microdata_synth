#!/usr/bin/env Rscript
# Quick Examples: Multi-Key Linking

# ============================================================================
# EXAMPLE 1: Explore Available Keys
# ============================================================================

cat("\n=== EXAMPLE 1: EXPLORING LINKING KEYS ===\n")

source("R/main.R")

# See all 19 known join keys
keys <- explore_join_keys()

# See which key types exist
find_datasets_by_key_type("person")    # 332 datasets
find_datasets_by_key_type("business")  # 18 datasets  
find_datasets_by_key_type("job")       # 8-10 datasets

# Get keys used in a specific dataset
get_dataset_keys("GBAPERSOONTAB")

# ============================================================================
# EXAMPLE 2: Link Datasets by Person ID (Most Common)
# ============================================================================

cat("\n=== EXAMPLE 2: PERSON-BASED LINKING ===\n")

# Generate person + household + income data with auto-detected keys
set.seed(123)
synthetic_person <- generate_linked_datasets(
  dataset_names = c("GBAPERSOONTAB", "GBAHUISHOUDENSBUS", "INPATAB"),
  n_records = list(
    GBAPERSOONTAB = 500,
    GBAHUISHOUDENSBUS = 150,
    INPATAB = 1000
  )
)

# Check integrity (auto-detects all key columns)
check_referential_integrity(synthetic_person)

# All datasets are linked via RINPERSOON (person ID)
# Plus any other key types found in the datasets

# ============================================================================
# EXAMPLE 3: Link Datasets by Business ID
# ============================================================================

cat("\n=== EXAMPLE 3: BUSINESS-BASED LINKING ===\n")

# Find datasets using BEID (Business Entity ID)
business_datasets <- find_linkable_datasets("BEID")

# Generate linked business data
# (if datasets with BEID exist)
# synthetic_business <- generate_linked_datasets(
#   c("POLISBUS", "BETAB", "WERKNEMERSKENMERKEN"),
#   n_records = 300,
#   link_by = "BEID"  # explicitly use business key
# )

# ============================================================================
# EXAMPLE 4: Link Datasets by Job ID
# ============================================================================

cat("\n=== EXAMPLE 4: JOB-BASED LINKING ===\n")

# Find datasets using job IDs
job_datasets <- find_datasets_by_key_type("job")

# IKVID is modern (2010+), BAANRUGID is older
# Generate linked employment data
# synthetic_jobs <- generate_linked_datasets(
#   c("GBAPERSOONTAB", "SPOLISBUS", "SPOLISLONGBAANTAB"),
#   n_records = 400,
#   link_by = "IKVID"
# )

# ============================================================================
# EXAMPLE 5: Auto-Detect All Keys
# ============================================================================

cat("\n=== EXAMPLE 5: AUTO-DETECT KEYS ===\n")

# Don't specify link_by - let it auto-detect all key types
synthetic_auto <- generate_linked_datasets(
  dataset_names = c("GBAPERSOONTAB", "GBAHUISHOUDENSBUS"),
  n_records = 200,
  # link_by = NULL  # auto-detect (this is the default)
)

# Will automatically:
# 1. Find all key columns in GBAPERSOONTAB
# 2. Identify their key types (person, household, etc.)
# 3. Generate appropriate IDs
# 4. Link GBAHUISHOUDENSBUS using those IDs
# 5. Validate referential integrity

# ============================================================================
# EXAMPLE 6: Multiple Keys in One Dataset
# ============================================================================

cat("\n=== EXAMPLE 6: MULTIPLE KEY TYPES ===\n")

# Some datasets have multiple key columns (e.g., both person AND job keys)
# The generator handles this automatically:

synthetic_multi <- generate_linked_datasets(
  c("GBAPERSOONTAB", "INPATAB"),
  n_records = 500
)

# Integrity report will show:
# - RINPERSOON linking: OK
# - IKVID linking: OK
# (and any other keys present)

# ============================================================================
# EXAMPLE 7: Validation with Multiple Keys
# ============================================================================

cat("\n=== EXAMPLE 7: VALIDATE MULTIPLE KEYS ===\n")

# check_referential_integrity() now validates all keys at once
integrity <- check_referential_integrity(
  datasets = synthetic_person,
  primary_dataset = "GBAPERSOONTAB",
  # key_cols = NULL  # auto-detect all keys
)

# Output shows:
# - Dataset | Key Column | N Rows | N Linked | N Orphaned | % Linked | OK?
# - GBAHUISHOUDENSBUS | RINPERSOON | 150 | 150 | 0 | 100% | OK
# - GBAHUISHOUDENSBUS | HUESSION | 150 | 150 | 0 | 100% | OK
# - INPATAB | RINPERSOON | 1000 | 500 | 500 | 50% | PARTIAL
# (etc.)

# ============================================================================
# EXAMPLE 8: Find Datasets You Can Link
# ============================================================================

cat("\n=== EXAMPLE 8: FIND LINKABLE DATASETS ===\n")

# Which datasets can you link together?

# Via person ID (most options)
person_datasets <- find_linkable_datasets("RINPERSOON")  # 332 datasets!

# Via business ID
business_datasets <- find_linkable_datasets("BEID")  # 18 datasets

# Via job ID
job_datasets <- find_datasets_by_key_type("job")  # 8-10 datasets

# Via household
household_datasets <- find_datasets_by_key_type("household")

# Now generate linked data from any combination
# Example: mix of person + household + business keys
# synthetic_mixed <- generate_linked_datasets(
#   c("GBAPERSOONTAB", "GBAHUISHOUDENSBUS", "POLISBUS"),
#   n_records = 1000
# )

# ============================================================================
# EXAMPLE 9: Key Type Details
# ============================================================================

cat("\n=== EXAMPLE 9: KEY TYPE DETAILS ===\n")

# See all key types and their characteristics
all_keys <- get_join_keys()
print(all_keys)

# Key types are:
# - person (most common): 9-digit IDs
# - business: 8-digit IDs  
# - job: 12-digit IDs
# - household: 9-digit IDs
# - object: 9-10 digit IDs (addresses/buildings)
# - address: 10-digit IDs
# - education: 12-digit IDs

# ============================================================================
# EXAMPLE 10: Generate Metadata Report
# ============================================================================

cat("\n=== EXAMPLE 10: METADATA REPORT ===\n")

# After generation, you can inspect what keys were used
metadata_person <- get_dataset_metadata("GBAPERSOONTAB")
keys_person <- get_dataset_keys("GBAPERSOONTAB")

cat("\nKeys in GBAPERSOONTAB:\n")
print(keys_person)

# Shows:
# - Column name
# - Key type (person, household, etc.)
# - Description
# - Where used

# ============================================================================
# Complete Workflow Example
# ============================================================================

cat("\n=== COMPLETE WORKFLOW ===\n")

cat("Step 1: Explore available keys\n")
explore_join_keys()

cat("Step 2: Find linkable datasets\n")
person_datasets <- find_linkable_datasets("RINPERSOON")

cat("Step 3: Generate synthetic data with auto-detected keys\n")
synthetic <- generate_linked_datasets(
  dataset_names = c("GBAPERSOONTAB", "GBAHUISHOUDENSBUS"),
  n_records = list(GBAPERSOONTAB = 100, GBAHUISHOUDENSBUS = 40)
)

cat("Step 4: Validate all key relationships\n")
integrity <- check_referential_integrity(synthetic)

cat("Step 5: Export with data dictionaries\n")
export_datasets(synthetic, "output/multi_key_example")

for (ds_name in names(synthetic)) {
  meta <- get_dataset_metadata(ds_name)
  create_data_dictionary(
    synthetic[[ds_name]],
    metadata = meta,
    output_file = paste0("output/multi_key_example/", ds_name, "_codebook.csv")
  )
}

cat("\n✓ Complete workflow finished!\n")
cat("✓ Check output/multi_key_example/ for results\n")

# ============================================================================
# Summary
# ============================================================================

cat("
=== KEY FEATURES ===

1. Auto-Detection
   - Automatically finds all key types in datasets
   - Generates appropriate IDs for each type
   - Validates integrity across all keys

2. Multiple Key Support
   - Person (332 datasets)
   - Business (18 datasets)  
   - Job (8-10 datasets)
   - Household, Object, Address, Education

3. Flexible Linking
   - Auto-detect keys (default)
   - Manually specify keys (link_by parameter)
   - Mix and match key types

4. Comprehensive Validation
   - Per-key integrity checking
   - Orphan detection
   - Detailed reports

5. Backward Compatible
   - Existing code still works
   - Just enhanced with more capabilities

=== TRY IT ===

# Quick test
source('R/main.R')
explore_join_keys()
synthetic <- generate_linked_datasets(
  c('GBAPERSOONTAB', 'GBAHUISHOUDENSBUS'),
  n_records = 50
)
check_referential_integrity(synthetic)
")
