# Data Export ---------------------------------------------------------------
# Functions to export synthetic data to CSV and RDS formats

#' Export Data to Files
#'
#' Exports synthetic data to CSV and/or RDS format
#'
#' @param data A tibble with synthetic data
#' @param output_dir Directory where files will be saved
#' @param dataset_name Name of the dataset (used in filenames)
#' @param format Vector of formats: "csv", "rds", or both (default)
#' @param overwrite If TRUE, overwrite existing files
#'
#' @return A list with export results
#'
#' @export
export_data <- function(data,
                        output_dir = "./output",
                        dataset_name = NULL,
                        format = c("csv", "rds"),
                        overwrite = TRUE) {
  stopifnot(
    is.data.frame(data),
    is.character(output_dir),
    is.character(format)
  )

  format <- match.arg(format, choices = c("csv", "rds"), several.ok = TRUE)

  # Infer dataset name from data attributes if not provided
  if (is.null(dataset_name)) {
    dataset_name <- attr(data, "dataset_name") %||%
                     attr(data, "name") %||%
                     "synthetic_data"
  }

  # Create output directory
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  exported_files <- character()

  # Export to CSV
  if ("csv" %in% format) {
    csv_path <- file.path(output_dir, paste0(dataset_name, ".csv"))
    if (file.exists(csv_path) && !overwrite) {
      cli::cli_warn("File {.file {csv_path}} already exists, skipping")
    } else {
      readr::write_csv(data, csv_path)
      exported_files <- c(exported_files, csv_path)
      cli::cli_alert_success("Exported CSV: {.file {csv_path}}")
    }
  }

  # Export to RDS
  if ("rds" %in% format) {
    rds_path <- file.path(output_dir, paste0(dataset_name, ".rds"))
    if (file.exists(rds_path) && !overwrite) {
      cli::cli_warn("File {.file {rds_path}} already exists, skipping")
    } else {
      saveRDS(data, rds_path)
      exported_files <- c(exported_files, rds_path)
      cli::cli_alert_success("Exported RDS: {.file {rds_path}}")
    }
  }

  invisible(list(
    dataset_name = dataset_name,
    n_rows = nrow(data),
    n_cols = ncol(data),
    exported_files = exported_files,
    output_dir = output_dir
  ))
}

#' Export Multiple Datasets
#'
#' Batch export multiple synthetic datasets to files
#'
#' @param datasets A named list of tibbles with synthetic data
#' @param output_dir Base output directory
#' @param format Vector of formats: "csv", "rds", or both
#' @param organize_by_dataset If TRUE, create subdirectories per dataset
#' @param verbose If TRUE, print progress
#'
#' @return A list with export results for all datasets
#'
#' @export
export_datasets <- function(datasets,
                            output_dir = "./output",
                            format = c("csv", "rds"),
                            organize_by_dataset = FALSE,
                            verbose = TRUE) {
  stopifnot(is.list(datasets), is.character(output_dir))

  results <- purrr::imap(datasets, ~ {
    ds_name <- .y
    ds_data <- .x

    # Determine output path
    out_path <- if (organize_by_dataset) {
      file.path(output_dir, ds_name)
    } else {
      output_dir
    }

    if (verbose) {
      cli::cli_progress_step("Exporting {ds_name}...")
    }

    export_data(ds_data, out_path, dataset_name = ds_name, format = format)
  })

  if (verbose) {
    cli::cli_alert_success("Exported {length(results)} dataset(s) to {.file {output_dir}}")
  }

  invisible(results)
}

#' Load Data from Files
#'
#' Load exported synthetic data back into R
#'
#' @param filepath Path to CSV or RDS file
#' @param format If NULL, inferred from file extension
#'
#' @return A tibble with the data
#'
#' @export
load_data <- function(filepath, format = NULL) {
  stopifnot(file.exists(filepath))

  if (is.null(format)) {
    format <- tools::file_ext(filepath)
  }

  switch(tolower(format),
    "csv" = readr::read_csv(filepath, show_col_types = FALSE),
    "rds" = readRDS(filepath),
    cli::cli_abort("Unknown format: {format}")
  )
}

#' Create Data Dictionary
#'
#' Generates a data dictionary (codebook) for exported data
#'
#' @param data A tibble with synthetic data
#' @param metadata Optional metadata to include descriptions
#' @param output_file Optional: save to CSV file
#'
#' @return A tibble with data dictionary
#'
#' @export
create_data_dictionary <- function(data, metadata = NULL, output_file = NULL) {
  stopifnot(is.data.frame(data))

  dictionary <- purrr::imap_dfr(data, ~ {
    col_name <- .y
    col_data <- .x

    var_meta <- if (!is.null(metadata) && col_name %in% names(metadata$variables)) {
      metadata$variables[[col_name]]
    } else {
      NULL
    }

    tibble::tibble(
      variable = col_name,
      type = class(col_data)[1],
      n_missing = sum(is.na(col_data)),
      pct_missing = round(100 * mean(is.na(col_data)), 1),
      n_unique = length(unique(col_data)),
      min = if (is.numeric(col_data)) min(col_data, na.rm = TRUE) else NA,
      max = if (is.numeric(col_data)) max(col_data, na.rm = TRUE) else NA,
      description = var_meta$description %||% NA_character_,
      data_type_catalogus = var_meta$data_type %||% NA_character_
    )
  })

  if (!is.null(output_file)) {
    readr::write_csv(dictionary, output_file)
    cli::cli_alert_success("Data dictionary saved to {.file {output_file}}")
  }

  dictionary
}

#' Generate Summary Statistics
#'
#' Creates a summary statistics report for exported data
#'
#' @param data A tibble
#' @param output_file Optional: save to CSV file
#'
#' @return A list with summary statistics
#'
#' @export
summary_statistics <- function(data, output_file = NULL) {
  stopifnot(is.data.frame(data))

  numeric_cols <- names(data)[sapply(data, is.numeric)]
  character_cols <- names(data)[sapply(data, is.character)]
  date_cols <- names(data)[sapply(data, inherits, what = "Date")]

  summary_list <- list()

  # Numeric summaries
  if (length(numeric_cols) > 0) {
    numeric_summary <- purrr::map_dfr(numeric_cols, ~ {
      col_data <- data[[.]]
      tibble::tibble(
        variable = .,
        type = "numeric",
        n = sum(!is.na(col_data)),
        mean = mean(col_data, na.rm = TRUE),
        sd = sd(col_data, na.rm = TRUE),
        min = min(col_data, na.rm = TRUE),
        q25 = quantile(col_data, 0.25, na.rm = TRUE),
        median = median(col_data, na.rm = TRUE),
        q75 = quantile(col_data, 0.75, na.rm = TRUE),
        max = max(col_data, na.rm = TRUE)
      )
    })
    summary_list$numeric <- numeric_summary
  }

  # Character summaries
  if (length(character_cols) > 0) {
    character_summary <- purrr::map_dfr(character_cols, ~ {
      col_data <- data[[.]]
      col_counts <- table(col_data, useNA = "ifany")
      top_value <- if (length(col_counts) > 0) {
        names(sort(col_counts, decreasing = TRUE))[1]
      } else {
        NA_character_
      }
      top_freq <- if (length(col_counts) > 0) {
        as.integer(max(col_counts))
      } else {
        NA_integer_
      }
      tibble::tibble(
        variable = .,
        type = "character",
        n = length(col_data),
        n_unique = length(unique(col_data)),
        top_value = top_value,
        top_freq = top_freq
      )
    })
    summary_list$character <- character_summary
  }

  # Date summaries
  if (length(date_cols) > 0) {
    date_summary <- purrr::map_dfr(date_cols, ~ {
      col_data <- data[[.]]
      tibble::tibble(
        variable = .,
        type = "date",
        n = sum(!is.na(col_data)),
        min_date = min(col_data, na.rm = TRUE),
        max_date = max(col_data, na.rm = TRUE)
      )
    })
    summary_list$date <- date_summary
  }

  if (!is.null(output_file)) {
    output <- purrr::list_rbind(summary_list, names_to = "summary_type")
    readr::write_csv(output, output_file)
    cli::cli_alert_success("Summary statistics saved to {.file {output_file}}")
  }

  summary_list
}

#' Compare Original and Synthetic Data
#'
#' Creates side-by-side comparison of original and synthetic data distributions
#'
#' @param synthetic_data Tibble with synthetic data
#' @param original_data Optional: tibble with original data for comparison
#' @param metric Metric to compare: "distribution", "summary", or "both"
#'
#' @return A tibble or list with comparison results
#'
#' @export
compare_datasets <- function(synthetic_data,
                             original_data = NULL,
                             metric = "summary") {
  stopifnot(is.data.frame(synthetic_data))

  comparison <- list(
    synthetic = data_quality_report(synthetic_data)
  )

  if (!is.null(original_data)) {
    stopifnot(is.data.frame(original_data))
    comparison$original <- data_quality_report(original_data)
  }

  comparison
}
