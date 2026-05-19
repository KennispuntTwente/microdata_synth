# Data Validation ----------------------------------------------------------
# Functions to validate generated synthetic data against metadata

#' Validate Data Against Metadata
#'
#' Checks data types, required columns, value ranges, and other constraints
#'
#' @param data A tibble with synthetic data
#' @param metadata Metadata from `get_dataset_metadata()`
#' @param verbose If TRUE, print detailed validation results
#'
#' @return A list with validation results and issues
#'
#' @export
validate_data <- function(data, metadata, verbose = TRUE) {
  stopifnot(is.data.frame(data), is.list(metadata))

  issues <- character()

  # 1. Check for required columns
  expected_cols <- names(metadata$variables)
  actual_cols <- names(data)
  missing_cols <- setdiff(expected_cols, actual_cols)
  extra_cols <- setdiff(actual_cols, expected_cols)

  if (length(missing_cols) > 0) {
    issues <- c(issues, glue::glue("Missing columns: {paste(missing_cols, collapse=', ')}"))
  }

  if (length(extra_cols) > 0) {
    cli::cli_alert_info("Found extra columns: {paste(extra_cols, collapse=', ')}")
  }

  # 2. Check data types
  type_issues <- character()
  for (col in intersect(expected_cols, actual_cols)) {
    var_meta <- metadata$variables[[col]]
    expected_type <- tolower(var_meta$data_type)
    actual_type <- class(data[[col]])[1]

    type_ok <- .check_type_compatibility(actual_type, expected_type)

    if (!type_ok) {
      type_issues <- c(type_issues,
                      glue::glue("{col}: expected {expected_type}, got {actual_type}"))
    }
  }

  if (length(type_issues) > 0) {
    issues <- c(issues, type_issues)
  }

  # 3. Check for missing values
  na_counts <- colSums(is.na(data))
  na_rates <- na_counts / nrow(data)

  high_na_cols <- names(na_counts)[na_rates > 0.1]
  if (length(high_na_cols) > 0) {
    cli::cli_alert_warning("Columns with >10% missing values: {paste(high_na_cols, collapse=', ')}")
  }

  # 4. Summary statistics
  valid <- length(issues) == 0

  result <- list(
    dataset_name = metadata$dataset_name,
    dataset_full_name = metadata$full_name,
    n_rows = nrow(data),
    n_cols = ncol(data),
    valid = valid,
    issues = issues,
    na_rates = na_rates,
    missing_columns = missing_cols,
    extra_columns = extra_cols
  )

  # Print summary if verbose
  if (verbose) {
    .print_validation_summary(result)
  }

  invisible(result)
}

#' Check Referential Integrity
#'
#' Verifies that foreign keys in datasets reference valid primary keys in parent dataset(s)
#' Supports multiple key types (person, business, job, etc.)
#'
#' @param datasets List of tibbles with synthetic data
#' @param primary_dataset Name of primary (parent) dataset (default: first dataset)
#' @param key_cols Optional: specific key column names to check
#'   If NULL, auto-detects all key columns from primary dataset
#' @param verbose If TRUE, print integrity report
#'
#' @return A tibble with integrity check results per dataset and key type
#'
#' @export
check_referential_integrity <- function(datasets,
                                        primary_dataset = NULL,
                                        key_cols = NULL,
                                        verbose = TRUE) {
  stopifnot(is.list(datasets))

  # Set primary dataset
  if (is.null(primary_dataset)) {
    primary_dataset <- names(datasets)[1]
  }

  if (!primary_dataset %in% names(datasets)) {
    cli::cli_warn("Primary dataset {.val {primary_dataset}} not found in datasets")
    return(invisible(NULL))
  }

  primary_data <- datasets[[primary_dataset]]

  # Auto-detect keys if not specified
  if (is.null(key_cols)) {
    # Get metadata to find key columns
    tryCatch({
      primary_meta <- get_dataset_metadata(primary_dataset)
      key_cols <- names(primary_meta$variables)[
        sapply(primary_meta$variables, function(x) isTRUE(x$is_key))
      ]
    }, error = function(e) {
      cli::cli_warn("Could not auto-detect keys: {e$message}")
      key_cols <<- character()
    })
  }

  if (length(key_cols) == 0) {
    cli::cli_warn("No key columns found to check")
    return(invisible(NULL))
  }

  # Check each child dataset
  result <- purrr::imap_dfr(
    datasets[setdiff(names(datasets), primary_dataset)],
    ~ {
      ds <- .x
      ds_name <- .y

      common_key_cols <- intersect(key_cols, intersect(names(ds), names(primary_data)))

      # Check each key column
      ds_result <- purrr::map_dfr(key_cols, ~ {
        key_col <- .

        if (!key_col %in% names(ds)) {
          return(tibble::tibble(
            dataset = ds_name,
            key_column = key_col,
            n_rows = NA_integer_,
            n_linked = NA_integer_,
            n_orphaned = NA_integer_,
            pct_linked = NA_real_,
            integrity_ok = FALSE,
            note = "key not in dataset"
          ))
        }

        if (!key_col %in% names(primary_data)) {
          return(tibble::tibble(
            dataset = ds_name,
            key_column = key_col,
            n_rows = NA_integer_,
            n_linked = NA_integer_,
            n_orphaned = NA_integer_,
            pct_linked = NA_real_,
            integrity_ok = FALSE,
            note = "key not in primary dataset"
          ))
        }

        fk_vals <- ds[[key_col]]
        pk_vals <- primary_data[[key_col]]
        n_linked <- sum(fk_vals %in% pk_vals)
        n_orphaned <- nrow(ds) - n_linked

        tibble::tibble(
          dataset = ds_name,
          key_column = key_col,
          n_rows = nrow(ds),
          n_linked = n_linked,
          n_orphaned = n_orphaned,
          pct_linked = round(100 * n_linked / nrow(ds), 1),
          integrity_ok = n_orphaned == 0L,
          note = NA_character_
        )
      })

      # Mandatory tuple-level check: when multiple keys are shared between
      # child and primary datasets, validate the full key tuple membership.
      tuple_result <- if (length(common_key_cols) >= 2) {
        child_keys <- ds[, common_key_cols, drop = FALSE]
        parent_keys <- primary_data[, common_key_cols, drop = FALSE]

        child_key_sig <- apply(child_keys, 1, paste, collapse = "\r")
        parent_key_sig <- apply(parent_keys, 1, paste, collapse = "\r")

        n_linked_tuple <- sum(child_key_sig %in% parent_key_sig)
        n_orphaned_tuple <- nrow(ds) - n_linked_tuple

        tibble::tibble(
          dataset = ds_name,
          key_column = paste(common_key_cols, collapse = " + "),
          n_rows = nrow(ds),
          n_linked = n_linked_tuple,
          n_orphaned = n_orphaned_tuple,
          pct_linked = round(100 * n_linked_tuple / nrow(ds), 1),
          integrity_ok = n_orphaned_tuple == 0L,
          note = "tuple-level check"
        )
      } else {
        tibble::tibble()
      }

      dplyr::bind_rows(ds_result, tuple_result)
    }
  )

  if (verbose) {
    .print_integrity_report(result, primary_dataset, key_cols)
  }

  invisible(result)
}

#' Check for Duplicates
#'
#' Identifies duplicate rows in the data
#'
#' @param data A tibble
#' @param by Columns to check for duplicates (NULL = all columns)
#'
#' @return A tibble with duplicate rows
#'
#' @export
check_duplicates <- function(data, by = NULL) {
  stopifnot(is.data.frame(data))

  if (is.null(by)) {
    by <- names(data)
  }

  data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::filter(dplyr::n() > 1) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(by)))
}

#' Summarize Data Quality
#'
#' Generates a data quality report with key statistics
#'
#' @param data A tibble
#' @param metadata Optional metadata to include type checking
#'
#' @return A list with data quality metrics
#'
#' @export
data_quality_report <- function(data, metadata = NULL) {
  stopifnot(is.data.frame(data))

  report <- list(
    n_rows = nrow(data),
    n_cols = ncol(data),
    completeness = colSums(!is.na(data)) / nrow(data),
    unique_values = purrr::map_int(data, ~ length(unique(.))),
    data_types = purrr::map_chr(data, ~ class(.)[1]),
    memory_size = format(object.size(data), units = "MB")
  )

  if (!is.null(metadata) && is.list(metadata)) {
    report$validation <- validate_data(data, metadata, verbose = FALSE)
  }

  report
}

# Helper functions ========================================================

#' Check Type Compatibility
#'
#' @keywords internal
.check_type_compatibility <- function(actual, expected) {
  # Skip check when data_type is missing from the catalogus
  if (is.na(expected) || nchar(trimws(expected)) == 0) return(TRUE)

  # Parse the expected type spec (e.g., "char(8)" -> "char", "num(2)" -> "num")
  parsed <- .parse_data_type(expected)
  expected_base <- parsed$type

  if (actual == expected_base) return(TRUE)
  if (actual == expected) return(TRUE)  # Exact match

  # Allow character types to be compatible
  if (expected_base %in% c("char", "varchar", "character") &&
      actual %in% c("character", "factor")) return(TRUE)

  # Allow numeric types (num, numeric, integer) to be interchangeable
  if (expected_base %in% c("num", "numeric", "integer") &&
      actual %in% c("numeric", "integer")) return(TRUE)

  FALSE
}

#' Parse Data Type Specification
#'
#' Parses SQL type specs like "char(8)", "varchar(100)" into base type and length
#'
#' @keywords internal
.parse_data_type <- function(data_type_spec) {
  spec <- tolower(data_type_spec %||% "character")
  
  # Try to extract type and length from patterns like "char(8)" or "num(4)"
  if (grepl("^(char|varchar|num|numeric|int|integer)\\((\\d+)\\)", spec)) {
    type <- stringr::str_extract(spec, "^[a-z]+")
    type <- switch(type, "num" = "num", "int" = "integer", type)
    length_match <- stringr::str_extract(spec, "\\d+")
    length <- as.numeric(length_match)
    list(type = type, length = length)
  } else if (grepl("^(char|varchar)", spec)) {
    type <- stringr::str_extract(spec, "^(char|varchar)")
    list(type = type, length = NA)
  } else {
    list(type = spec, length = NA)
  }
}

#' Print Validation Summary
#'
#' @keywords internal
.print_validation_summary <- function(result) {
  cat("\n")
  cli::cli_h2("Data Validation Report")
  cli::cli_text("Dataset: {.val {result$dataset_name}}")
  cli::cli_text("Dimensions: {result$n_rows} rows × {result$n_cols} columns")

  if (result$valid) {
    cli::cli_alert_success("Data is valid")
  } else {
    cli::cli_alert_danger("Data has {length(result$issues)} issue(s)")
    for (issue in result$issues) {
      cli::cli_text("  • {issue}")
    }
  }

  # Missing values summary
  max_na_rate <- max(result$na_rates)
  if (max_na_rate > 0) {
    cli::cli_text("Missing values: {round(max_na_rate * 100, 1)}% max per column")
  }

  cat("\n")
}

#' Print Referential Integrity Report
#'
#' @keywords internal
.print_integrity_report <- function(result, primary_dataset, key_cols) {
  cat("\n")
  cli::cli_h2("Referential Integrity Report")
  cli::cli_text("Primary dataset: {.val {primary_dataset}}")
  cli::cli_text("Key columns: {paste(key_cols, collapse=', ')}")

  all_ok <- all(result$integrity_ok, na.rm = TRUE)

  if (all_ok) {
    cli::cli_alert_success("All datasets linked correctly")
  } else {
    n_issues <- sum(!result$integrity_ok, na.rm = TRUE)
    cli::cli_alert_warning("Found {n_issues} integrity issue(s)")
  }

  # Print summary table
  cat("\n")
  print(result, n = Inf)
  cat("\n")
}
