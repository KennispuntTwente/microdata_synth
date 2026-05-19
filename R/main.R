# Microdata Synth - Main Entry Point ======================================
# Load all modules and provide a clean API for users

# Required packages
required_packages <- c(
  "dplyr", "purrr", "stringr", "readr",
  "DBI", "RSQLite", "cli", "glue", "tibble", "rlang", "jsonlite"
)

# Check package availability only (do not attach/reload namespaces)
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(glue::glue(
      "Package '{pkg}' not installed. Run: renv::restore()"
    ))
  }
}

# Local fallback for `%||%` so sourced modules don't require attaching rlang.
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }
}

# Load modules
source("R/catalog_interface.R", local = TRUE)
source("R/data_generator.R", local = TRUE)
source("R/validation.R", local = TRUE)
source("R/export.R", local = TRUE)

# ============================================================================
# Main API Functions (exported to user)
# ============================================================================

#' Explore Available Datasets
#'
#' Interactive exploration of the microdata catalogus
#'
#' @export
explore_catalogus <- function() {
  cat("\n")
  cli::cli_h1("CBS Microdata Catalogus")

  stats <- get_catalogus_stats()
  cli::cli_text(
    "Database contains: {stats$n_datasets} datasets, {stats$n_variables} variables"
  )

  datasets <- list_datasets()
  cli::cli_h2("Datasets")
  print(head(datasets, 20), n = 20)

  invisible(datasets)
}

#' Explore Linking Keys
#'
#' Show all available linking/join keys in the catalogus
#'
#' @export
explore_join_keys <- function() {
  cat("\n")
  cli::cli_h1("CBS Linking Keys (Join Variables)")

  keys <- get_join_keys()
  cli::cli_h2("All Available Keys")
  print(keys, n = Inf)

  cat("\n")
  cli::cli_h2("Key Types Overview")
  key_summary <- get_key_type_overview()
  print(key_summary)

  invisible(keys)
}

#' Fuzzy Search Datasets
#'
#' Quick fuzzy search across dataset names and descriptions
#'
#' @param pattern Character string to search for (case-insensitive)
#' @param limit Maximum number of results to return
#'
#' @return A tibble of matching datasets
#'
#' @export
search_datasets_fuzzy <- function(pattern, limit = 10) {
  datasets <- list_datasets()

  matches <- datasets |>
    dplyr::filter(
      stringr::str_detect(tolower(name), tolower(pattern)) |
        stringr::str_detect(tolower(description %||% ""), tolower(pattern))
    ) |>
    dplyr::select(name, full_name, description, unit_of_observation)

  if (is.finite(limit)) {
    matches <- dplyr::slice_head(matches, n = limit)
  }

  if (nrow(matches) == 0) {
    cli::cli_alert("No datasets match {.val {pattern}}")
    return(tibble::tibble())
  }

  cli::cli_alert_info("Found {nrow(matches)} matching dataset(s)")
  print(matches, n = Inf)
  invisible(matches)
}

#' Search Datasets
#'
#' Unified search wrapper with selectable backend:
#' - "fuzzy": in-memory case-insensitive contains search
#' - "fts": SQLite full-text search with ranking
#' - "auto": try FTS first, then fall back to fuzzy if needed
#'
#' @param pattern Character string to search for
#' @param mode Search backend: "auto", "fuzzy", or "fts"
#' @param limit Maximum number of results to return
#'
#' @return A tibble of matching datasets
#'
#' @export
search_datasets <- function(pattern, mode = c("auto", "fuzzy", "fts"), limit = 10) {
  stopifnot(is.character(pattern), length(pattern) == 1)
  mode <- match.arg(mode)

  if (mode == "fuzzy") {
    return(search_datasets_fuzzy(pattern, limit = limit))
  }

  if (mode == "fts") {
    return(search_datasets_fts(pattern, limit = limit))
  }

  # mode == "auto": prefer FTS, fall back to fuzzy when unavailable/failing.
  fts_result <- tryCatch(
    search_datasets_fts(pattern, limit = limit),
    error = function(e) {
      cli::cli_alert_info("FTS search unavailable; falling back to fuzzy search")
      NULL
    }
  )

  if (!is.null(fts_result) && nrow(fts_result) > 0) {
    return(fts_result)
  }

  search_datasets_fuzzy(pattern, limit = limit)
}

#' Find Datasets to Link
#'
#' Find datasets that share the same linking keys for creating linked data
#'
#' @param key_name Optional: specific key name to search for
#' @param key_type Optional: key type (person, business, job, etc.)
#'
#' @export
find_linkable_datasets <- function(key_name = "RINPERSOON", key_type = NULL) {
  if (!is.null(key_name)) {
    conn <- .get_catalogus_conn()
    on.exit(DBI::dbDisconnect(conn))

    result <- DBI::dbGetQuery(
      conn,
      "
      SELECT DISTINCT
        d.name,
        d.full_name,
        d.unit_of_observation,
        v.key_type,
        COUNT(*) as n_key_columns
      FROM datasets d
      JOIN variables v ON v.dataset_id = d.id
      WHERE v.is_key = 1 AND UPPER(v.name) = UPPER(?)
      GROUP BY d.id, d.name, d.full_name, d.unit_of_observation, v.key_type
      ORDER BY d.name
      ",
      params = list(key_name)
    )

    if (nrow(result) == 0) {
      cli::cli_alert("No datasets found with key {.val {key_name}}")
      return(tibble::tibble())
    }

    cli::cli_h2("Datasets linked by {.val {key_name}}")
    print(tibble::as_tibble(result), n = Inf)
    invisible(tibble::as_tibble(result))
  } else if (!is.null(key_type)) {
    find_datasets_by_key_type(key_type)
  }
}

#' Generate Complete Synthetic Dataset Suite
#'
#' Convenience function to generate a complete suite of linked datasets
#'
#' @param datasets Character vector of dataset names to generate
#' @param primary_n Number of primary dataset records
#' @param output_dir Directory to save files
#' @param format Export format: "csv", "rds", or both
#' @param validate If TRUE, validate and show validation report
#' @param verbose If TRUE, print progress
#'
#' @return A list of generated tibbles
#'
#' @export
generate_suite <- function(datasets = c("GBAPERSOONTAB", "GBAHUISHOUDENSBUS"),
                          primary_n = 100,
                          output_dir = "./output",
                          format = c("csv", "rds"),
                          validate = TRUE,
                          verbose = TRUE) {
  if (verbose) {
    cli::cli_h1("Generating Synthetic Data Suite")
    cli::cli_text("Datasets: {paste(datasets, collapse=', ')}")
    cli::cli_text("Primary records: {primary_n}")
  }

  # Generate data
  synthetic <- generate_linked_datasets(
    dataset_names = datasets,
    n_records = primary_n
  )

  # Validate
  if (validate) {
    cli::cli_h2("Validation Results")
    purrr::iwalk(synthetic, ~ {
      metadata <- get_dataset_metadata(.y)
      validate_data(.x, metadata)
    })

    # Check referential integrity
    check_referential_integrity(synthetic)
  }

  # Export
  if (verbose) {
    cli::cli_h2("Exporting Data")
  }

  export_datasets(
    synthetic,
    output_dir = output_dir,
    format = format,
    verbose = verbose
  )

  if (verbose) {
    cli::cli_alert_success("Complete! Data saved to {.file {output_dir}}")
  }

  invisible(synthetic)
}

#' Quick-Start Synthetic Data Generation
#'
#' Minimal example: generate one dataset and export
#'
#' @param dataset_name Name of dataset to generate
#' @param n_records Number of records
#' @param output_dir Output directory
#'
#' @return The generated tibble
#'
#' @export
generate_quick <- function(dataset_name = "GBAPERSOONTAB",
                          n_records = 100,
                          output_dir = "./output") {
  cli::cli_text("Generating {n_records} records for {.val {dataset_name}}...")

  data <- generate_synthetic_data(dataset_name, n_records)

  cli::cli_text("Exporting to {.file {output_dir}}...")
  export_data(data, output_dir, dataset_name)

  data
}

# ============================================================================
# Session Setup
# ============================================================================

.onLoad <- function(libname, pkgname) {
  # This would run if this were a package, but for a script context:
  # Just make sure key variables are available
  invisible(NULL)
}

# ============================================================================
# Information & Help
# ============================================================================

#' Get Help on Microdata Synth
#'
#' @export
synth_help <- function() {
  cat("
Microdata Synth: Synthetic CBS Microdata Generator
====================================================

QUICK START:
  1. search_datasets(\"person\")      # Fuzzy search for datasets
  2. explore_catalogus()           # See all available datasets
  3. explore_join_keys()           # See available linking keys
  4. generate_quick(\"GBAPERSOONTAB\")    # Generate synthetic data
  5. generate_suite()              # Generate linked datasets

SEARCHING FOR DATASETS:
  search_datasets(\"person\")        # Find datasets with \"person\" in name/description
  search_datasets(\"inko\")          # Fuzzy search (case-insensitive)

EXPLORING LINKING KEYS:
  # See all available keys (person, business, job, household, etc.)
  explore_join_keys()

  # Find datasets you can link together
  find_linkable_datasets(\"RINPERSOON\")  # person-based linking
  find_linkable_datasets(\"BEID\")        # business-based linking
  find_datasets_by_key_type(\"job\")      # all job-related datasets

  # Get keys used in a specific dataset
  get_dataset_keys(\"GBAPERSOONTAB\")

DETAILED WORKFLOW - SINGLE DATASET:
  # Get metadata
  meta <- get_dataset_metadata(\"GBAPERSOONTAB\")

  # Generate data
  data <- generate_synthetic_data(\"GBAPERSOONTAB\", n_records = 1000)

  # Validate
  validate_data(data, meta)

  # Export
  export_data(data, \"./output\", \"GBAPERSOONTAB\")

DETAILED WORKFLOW - LINKED DATASETS:
  # Auto-detect linking keys and generate
  synthetic <- generate_linked_datasets(
    c(\"GBAPERSOONTAB\", \"GBAHUISHOUDENSBUS\"),
    n_records = 500
  )

  # Validate links (auto-detects all key types)
  check_referential_integrity(synthetic)

KEY FUNCTIONS:
  Exploration:     search_datasets(), list_datasets(), explore_join_keys(),
                   find_linkable_datasets(), get_dataset_keys()
  Generation:      generate_synthetic_data(), generate_linked_datasets()
  Validation:      validate_data(), check_referential_integrity()
  Export:          export_data(), export_datasets(), load_data()

LINKING KEY TYPES (7 types available):
  - person:     RINPERSOON (303 datasets) - most common
  - business:   BEID (15 datasets)
  - job:        IKVID, BAANRUGID (8-10 datasets)
  - household:  HUESSION (5+ datasets)
  - object:     RINOBJECT, VSLSLEUTELBUS (address/dwelling)
  - address:    ADRESRUGNR (address backbone)
  - education:  OGESSION (education enrollment)

For detailed help: ?<function_name>
  ")
  invisible(NULL)
}

# Print startup message
if (interactive()) {
  cat("
╔══════════════════════════════════════════════════════════════╗
║  Microdata Synth: CBS Synthetic Microdata Generator          ║
║  Type: synth_help()  for quick start guide                   ║
║        explore_catalogus()  to see available datasets        ║
║        explore_join_keys()  to see all linking keys          ║
╚══════════════════════════════════════════════════════════════╝
  ")
}
