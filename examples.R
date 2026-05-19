#!/usr/bin/env Rscript
# ============================================================================
# Example: Using the Synthetic Data Generator
# ============================================================================
# This script demonstrates various use cases of the microdata_synth generator

# Load the environment
source("renv/activate.R")

# Load all modules
source("R/main.R")

# ============================================================================
# EXAMPLE 1: Explore the Catalogus
# ============================================================================

cat("\n\n=== EXAMPLE 1: EXPLORE CATALOGUS ===\n")

# See what datasets are available
datasets <- list_datasets()
print(head(datasets, 10))

# Get statistics
stats <- get_catalogus_stats()
cat("\nDatabase stats:\n")
print(stats)

# Search for specific datasets
cat("\nSearching for 'loon' (wage) datasets:\n")
results <- search_datasets("loon")


# ============================================================================
# EXAMPLE 2: Generate Single Dataset
# ============================================================================

cat("\n\n=== EXAMPLE 2: GENERATE SINGLE DATASET ===\n")

# Get metadata for SECMBUS dataset
metadata <- get_dataset_metadata("SECMBUS")
cat("Dataset:", metadata$dataset_name, "\n")
cat("Variables:", paste(names(metadata$variables), collapse = ", "), "\n")

# List variables with details
variables <- list_variables("SECMBUS")
print(variables)

# Generate synthetic data
set.seed(42)
secmbus <- generate_synthetic_data(
  dataset_name = "SECMBUS",
  n_records = 100
)

cat("\nGenerated data:\n")
print(head(secmbus, 10))

# ============================================================================
# EXAMPLE 3: Validate Generated Data
# ============================================================================

cat("\n\n=== EXAMPLE 3: VALIDATE GENERATED DATA ===\n")

# Validate against metadata
validation <- validate_data(secmbus, metadata, verbose = TRUE)

# Check for duplicates
cat("\nChecking for duplicate records:\n")
duplicates <- check_duplicates(secmbus, by = "RINPERSOON")
cat("Found", nrow(duplicates), "duplicate RINPERSOON values\n")

# Data quality report
quality <- data_quality_report(secmbus, metadata)
cat("\nData quality:\n")
cat("Memory size:", quality$memory_size, "\n")
cat("Complete cases:", sum(complete.cases(secmbus)), "/", nrow(secmbus), "\n")

# ============================================================================
# EXAMPLE 4: Generate Multiple Linked Datasets
# ============================================================================

cat("\n\n=== EXAMPLE 4: GENERATE LINKED DATASETS ===\n")

# Generate multiple datasets with proper linking
set.seed(123)

# First, let's see what datasets are available
available <- list_datasets()$name
cat("First 10 available datasets:\n")
print(head(available, 10))

# Generate linked datasets
synthetic_datasets <- generate_linked_datasets(
  dataset_names = c("GBAPERSOONTAB", "GBAHUISHOUDENSBUS"),
  n_records = 50,  # 50 primary records, household records sampled from them
  seed = 456
)

# Check what we got
cat("\nGenerated datasets:\n")
for (name in names(synthetic_datasets)) {
  df <- synthetic_datasets[[name]]
  cat("  ", name, ": ", nrow(df), "rows ×", ncol(df), "cols\n")
}

# Check referential integrity
integrity <- check_referential_integrity(synthetic_datasets)
print(integrity)

# ============================================================================
# EXAMPLE 5: Export Data
# ============================================================================

cat("\n\n=== EXAMPLE 5: EXPORT DATA ===\n")

# Create output directory
output_dir <- "output/example_export"

# Export single dataset
cat("Exporting SECMBUS...\n")
export_data(
  secmbus,
  output_dir = output_dir,
  dataset_name = "SECMBUS",
  format = c("csv", "rds")
)

# Create and export data dictionary
cat("\nCreating data dictionary...\n")
dictionary <- create_data_dictionary(
  secmbus,
  metadata = metadata,
  output_file = file.path(output_dir, "SECMBUS_dictionary.csv")
)
print(dictionary)

# Export summary statistics
cat("\nGenerating summary statistics...\n")
stats <- summary_statistics(
  secmbus,
  output_file = file.path(output_dir, "SECMBUS_summary.csv")
)

# ============================================================================
# EXAMPLE 6: Export Multiple Datasets with Organization
# ============================================================================

cat("\n\n=== EXAMPLE 6: EXPORT MULTIPLE DATASETS ===\n")

# Collect metadata for all datasets
metadatas <- list(
  GBAPERSOONTAB = get_dataset_metadata("GBAPERSOONTAB"),
  GBAHUISHOUDENSBUS = get_dataset_metadata("GBAHUISHOUDENSBUS")
)

# Export all datasets
export_datasets(
  synthetic_datasets,
  output_dir = file.path(output_dir, "datasets"),
  format = c("csv", "rds"),
  organize_by_dataset = TRUE,
  verbose = TRUE
)

# ============================================================================
# EXAMPLE 7: Generate Large Dataset
# ============================================================================

cat("\n\n=== EXAMPLE 7: GENERATE LARGE DATASET ===\n")

# Generate a larger dataset
cat("Generating 10,000 synthetic persons...\n")
large_secmbus <- generate_synthetic_data(
  dataset_name = "SECMBUS",
  n_records = 10000,
  seed = 789
)

cat("Generated:", nrow(large_secmbus), "rows\n")
cat("Memory size:", format(object.size(large_secmbus), units = "MB"), "\n")

# Quick stats
cat("\nQuick statistics:\n")
print(summary(large_secmbus))

# ============================================================================
# EXAMPLE 8: Load and Inspect Exported Data
# ============================================================================

cat("\n\n=== EXAMPLE 8: LOAD AND INSPECT EXPORTED DATA ===\n")

# List files in output directory
cat("Files in output:\n")
files <- list.files(output_dir, recursive = TRUE, full.names = FALSE)
print(files)

# Load a CSV file
csv_file <- file.path(output_dir, "SECMBUS.csv")
if (file.exists(csv_file)) {
  loaded_data <- load_data(csv_file, format = "csv")
  cat("\nLoaded data from CSV:\n")
  print(head(loaded_data, 5))
}

# Load an RDS file
rds_file <- file.path(output_dir, "SECMBUS.rds")
if (file.exists(rds_file)) {
  loaded_rds <- load_data(rds_file, format = "rds")
  cat("\nLoaded data from RDS:\n")
  print(head(loaded_rds, 5))
}

# ============================================================================
# EXAMPLE 9: Using the Convenience Functions
# ============================================================================

cat("\n\n=== EXAMPLE 9: CONVENIENCE FUNCTIONS ===\n")

# Quick generation and export (one line!)
cat("Quick start - generating and exporting in one go:\n")
quick_data <- generate_quick(
  dataset_name = "SECMBUS",
  n_records = 200,
  output_dir = "output/quick_example"
)

cat("Generated and exported:", nrow(quick_data), "records\n")

# Complete suite with validation and export
cat("\nGenerating complete suite...\n")
suite <- generate_suite(
  datasets = c("GBAPERSOONTAB", "GBAHUISHOUDENSBUS"),
  primary_n = 500,
  output_dir = "output/suite_example",
  format = c("csv", "rds"),
  validate = TRUE,
  verbose = TRUE
)

# ============================================================================
# EXAMPLE 10: Advanced Usage - Custom Workflow
# ============================================================================

cat("\n\n=== EXAMPLE 10: CUSTOM WORKFLOW ===\n")

# Suppose you want to:
# 1. Generate data for specific datasets
# 2. Apply custom filtering/transformation
# 3. Validate with custom rules
# 4. Export with specific settings

set.seed(999)

# Step 1: Get metadata
cat("Step 1: Getting metadata...\n")
gba_persoon_meta <- get_dataset_metadata("GBAPERSOONTAB")
gba_huishoud_meta <- get_dataset_metadata("GBAHUISHOUDENSBUS")

# Step 2: Generate raw synthetic data
cat("Step 2: Generating synthetic data...\n")
n_records <- 1000
raw_gba_persoon <- generate_synthetic_data("GBAPERSOONTAB", n_records)

# Step 3: Custom transformation
# In real use, you might apply domain-specific business rules
cat("Step 3: Applying custom transformations...\n")
gba_persoon_transformed <- raw_gba_persoon

# Step 4: Detailed validation
cat("Step 4: Validating...\n")
gba_persoon_validation <- validate_data(gba_persoon_transformed, gba_persoon_meta, verbose = TRUE)

# Step 5: Export with metadata
cat("Step 5: Exporting with documentation...\n")
output_path <- "output/advanced_example"
dir.create(output_path, recursive = TRUE, showWarnings = FALSE)

export_data(gba_persoon_transformed, output_path, "GBAPERSOONTAB", format = c("csv", "rds"))

# Create comprehensive documentation
dictionary <- create_data_dictionary(
  gba_persoon_transformed,
  metadata = gba_persoon_meta,
  output_file = file.path(output_path, "GBAPERSOONTAB_codebook.csv")
)

summary_stats <- summary_statistics(
  gba_persoon_transformed,
  output_file = file.path(output_path, "GBAPERSOONTAB_summary.csv")
)

cat("\nWorkflow complete!\n")

# ============================================================================
# Summary
# ============================================================================

cat("\n\n")
cat("=" |> rep(70) |> paste(collapse = ""), "\n")
cat("EXAMPLES COMPLETE\n")
cat("=" |> rep(70) |> paste(collapse = ""), "\n")
cat("\nGenerated files are in the 'output/' directory\n")
cat("Check out the example outputs and modify for your use case!\n\n")
