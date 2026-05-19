# Data Generation Engine --------------------------------------------------
# Functions to generate realistic synthetic microdata

#' Generate Synthetic Data for a Single Dataset
#'
#' @param dataset_name Name of the dataset from the catalogus
#' @param n_records Number of records to generate
#' @param seed Optional random seed for reproducibility
#' @param key_ids Optional named list of key ID vectors to use for linking
#'   Example: list(RINPERSOON = persons$RINPERSOON, BEID = businesses$BEID)
#'   If a key is not provided, new IDs will be generated
#'
#' @return A tibble with synthetic data
#'
#' @export
generate_synthetic_data <- function(dataset_name,
                                    n_records = 100,
                                    seed = NULL,
                                    key_ids = NULL) {
  stopifnot(
    is.character(dataset_name), length(dataset_name) == 1,
    is.numeric(n_records), n_records > 0
  )

  if (!is.null(seed)) {
    set.seed(seed)
  }

  # Get metadata
  metadata <- get_dataset_metadata(dataset_name)

  # Parse dataset period to constrain date generation
  period_range <- .parse_dataset_period(metadata$period)

  # Identify key columns and their types
  key_cols <- list()
  for (var_name in names(metadata$variables)) {
    var_meta <- metadata$variables[[var_name]]
    if (isTRUE(var_meta$is_key)) {
      key_cols[[var_name]] <- var_meta$key_type %||% "person"
    }
  }

  # Start with a tibble with correct number of rows but no columns
  df <- tibble::tibble(.rows = n_records)

  # Generate each variable
  for (var_name in names(metadata$variables)) {
    var_meta <- metadata$variables[[var_name]]

    # Handle key columns
    if (var_name %in% names(key_cols)) {
      key_type <- key_cols[[var_name]]

      # Use provided IDs if available
      matched_key_name <- NULL
      if (!is.null(key_ids) && length(key_ids) > 0) {
        key_names <- names(key_ids)
        matched_idx <- match(toupper(var_name), toupper(key_names))
        if (!is.na(matched_idx)) {
          matched_key_name <- key_names[[matched_idx]]
        }
      }

      if (!is.null(matched_key_name)) {
        values <- key_ids[[matched_key_name]]
        # If we have more records than IDs, resample with replacement
        if (length(values) < n_records) {
          values <- sample(values, size = n_records, replace = TRUE)
        } else {
          values <- values[seq_len(n_records)]
        }
      } else {
        # For key columns that have an explicit code list in metadata
        # (e.g. RINPERSOONS source code), sample from those valid codes.
        if (!is.null(var_meta$code_list) && length(var_meta$code_list) > 0) {
          key_codes <- vapply(var_meta$code_list,
                              function(x) as.character(x[["value"]]),
                              character(1))
          values <- sample(key_codes, size = n_records, replace = TRUE)
        } else {
          # Otherwise generate new IDs based on key type
          values <- .generate_ids(n_records, key_type = key_type)
        }
      }
    } else {
      # Generate appropriate data type for non-key columns
      values <- .generate_variable(
        var_name     = var_name,
        n            = n_records,
        data_type    = var_meta$data_type,
        description  = var_meta$description,
        code_list    = var_meta$code_list,
        usage_notes  = var_meta$usage_notes,
        meta_length  = var_meta$meta_length,
        period_range = period_range
      )
    }

    df <- df |> dplyr::mutate(!!rlang::sym(var_name) := values)
  }

  # Post-processing: enforce dataset-level constraints
  df <- .apply_date_constraints(df, metadata$variables, period_range)
  df <- .apply_uniqueness_constraint(df, metadata, key_cols)

  df
}

#' Generate Multiple Linked Datasets
#'
#' @param dataset_names Vector of dataset names to generate
#' @param n_records Number of records per dataset (or named list with per-dataset counts)
#' @param seed Optional random seed
#' @param primary_dataset Name of the primary (parent) dataset to use for ID generation
#'   If NULL, uses the first dataset in the list
#' @param link_by Character vector of key column names to use for linking
#'   If NULL, auto-detects all key columns from the primary dataset
#'
#' @return A list of tibbles, one per dataset, with linked keys
#'
#' @export
generate_linked_datasets <- function(dataset_names,
                                     n_records = 100,
                                     seed = NULL,
                                     primary_dataset = NULL,
                                     link_by = NULL) {
  stopifnot(is.character(dataset_names), length(dataset_names) >= 1)

  if (!is.null(seed)) {
    set.seed(seed)
  }

  # Set primary dataset
  if (is.null(primary_dataset)) {
    primary_dataset <- dataset_names[1]
  }
  stopifnot(primary_dataset %in% dataset_names)

  # Handle per-dataset record counts
  if (is.numeric(n_records)) {
    n_records <- rlang::set_names(
      rep(n_records, length(dataset_names)),
      dataset_names
    )
  } else {
    stopifnot(is.list(n_records) || is.named(n_records))
  }

  # Get primary dataset metadata to identify keys
  primary_meta <- get_dataset_metadata(primary_dataset)
  
  # Auto-detect keys if not specified
  if (is.null(link_by)) {
    link_by <- names(primary_meta$variables)[
      sapply(primary_meta$variables, function(x) isTRUE(x$is_key))
    ]
  }
  
  if (length(link_by) == 0) {
    cli::cli_warn("No linking keys found in primary dataset {.val {primary_dataset}}")
    # Fall back to generating independent datasets
    return(purrr::imap(
      rlang::set_names(dataset_names),
      ~ generate_synthetic_data(.x, n_records = n_records[[.y]])
    ))
  }

  cli::cli_progress_step("Generating {primary_dataset} ({n_records[[primary_dataset]]} records)")
  
  # Generate primary dataset
  n_primary <- n_records[[primary_dataset]] %||% 100
  primary_data <- generate_synthetic_data(
    dataset_name = primary_dataset,
    n_records = n_primary,
    seed = seed
  )

  # Extract primary keys as a dataframe to preserve composite key row correspondence
  # (e.g. RINPERSOON + RINPERSOONS must always be sampled from the same row)
  key_col_positions <- sapply(link_by, function(k) match(toupper(k), toupper(names(primary_data))))
  valid_link_by     <- link_by[!is.na(key_col_positions)]
  primary_key_df    <- primary_data[, key_col_positions[!is.na(key_col_positions)], drop = FALSE]
  names(primary_key_df) <- toupper(valid_link_by)

  # Generate each dataset, linking via common keys
  result <- vector("list", length(dataset_names))
  names(result) <- dataset_names
  result[[primary_dataset]] <- primary_data

  for (ds_name in setdiff(dataset_names, primary_dataset)) {
    n_recs <- n_records[[ds_name]] %||% 100

    # Determine which keys to use and create linking IDs
    ds_meta <- get_dataset_metadata(ds_name)
    ds_key_cols <- names(ds_meta$variables)[
      sapply(ds_meta$variables, function(x) isTRUE(x$is_key))
    ]

    # Create key_ids list by finding common keys.
    # IMPORTANT: sample row indices ONCE so all composite key columns (e.g.
    # RINPERSOON + RINPERSOONS) are always taken from the same primary row,
    # preserving their combined uniqueness.
    ds_key_ids <- list()
    common_key_norms <- intersect(toupper(ds_key_cols), names(primary_key_df))
    if (length(common_key_norms) > 0) {
      n_available  <- nrow(primary_key_df)
      sampled_rows <- sample(n_available, size = n_recs, replace = (n_recs > n_available))
      for (key_col in ds_key_cols) {
        key_norm <- toupper(key_col)
        if (key_norm %in% names(primary_key_df)) {
          ds_key_ids[[key_col]] <- primary_key_df[[key_norm]][sampled_rows]
        }
      }
    }

    cli::cli_progress_step("Generating {ds_name} ({n_recs} records) linked to {primary_dataset}")
    result[[ds_name]] <- generate_synthetic_data(
      dataset_name = ds_name,
      n_records = n_recs,
      key_ids = ds_key_ids
    )
  }

  result
}

# Helper: Generate realistic values for a variable =====================

#' Generate IDs of Various Types
#'
#' Creates unique identification numbers following CBS format for different key types:
#' - person (RINPERSOON): 9-digit
#' - business (BEID): 6-8 digit
#' - job (IKVID, BAANRUGID): 12-16 digit
#' - household (HUESSION): 9-digit
#' - object (RINOBJECT): 9-digit
#' - address (ADRESRUGNR): 10-digit
#' - education (OGESSION): 12-digit
#'
#' @param n Number of IDs to generate
#' @param key_type Type of key (default: "person")
#' @param start_offset Starting number for ID generation
#'
#' @return A character vector of IDs
#'
#' @keywords internal
.generate_ids <- function(n, key_type = "person", start_offset = NULL) {
  key_type <- tolower(key_type)

  switch(key_type,
    "person" = {
      # 9-digit person identifier
      if (is.null(start_offset)) start_offset <- 100000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%09d", ids)
    },
    "business" = {
      # 8-digit business entity ID (BEID)
      if (is.null(start_offset)) start_offset <- 10000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%08d", ids)
    },
    "job" = {
      # 12-digit job identifier (IKVID)
      # Format: RRRRRRRYYJJJJ (R=person, Y=year, J=job number)
      if (is.null(start_offset)) start_offset <- 100000000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%012.0f", ids)  # %.0f handles doubles > 2^31
    },
    "household" = {
      # 9-digit household identifier (HUESSION)
      if (is.null(start_offset)) start_offset <- 100000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%09d", ids)
    },
    "object" = {
      # 9-digit object/dwelling identifier (RINOBJECT)
      if (is.null(start_offset)) start_offset <- 100000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%09d", ids)
    },
    "address" = {
      # 10-digit address backbone number (ADRESRUGNR)
      if (is.null(start_offset)) start_offset <- 1000000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%010d", ids)
    },
    "education" = {
      # 12-digit education identifier (OGESSION)
      if (is.null(start_offset)) start_offset <- 100000000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%012.0f", ids)  # %.0f handles doubles > 2^31
    },
    # Fallback to person
    {
      if (is.null(start_offset)) start_offset <- 100000000
      ids <- seq(start_offset, length.out = n)
      sprintf("%09d", ids)
    }
  )
}

#' Deprecated: Generate Person IDs (RINPERSOON)
#'
#' @keywords internal
.generate_person_ids <- function(n) {
  .generate_ids(n, key_type = "person")
}

#' Generate Values for a Variable
#'
#' Routes to appropriate generation function based on variable name and data type
#'
#' @param var_name Variable name (e.g., "GESLACHT", "GEBOORTEJAAR")
#' @param n Number of values to generate
#' @param data_type Data type (character, numeric, integer, date, logical)
#' @param description Variable description from metadata
#'
#' @return A vector of generated values
#'
#' @keywords internal
.generate_variable <- function(var_name, n, data_type, description,
                              code_list = NULL, usage_notes = NULL,
                              meta_length = NULL, period_range = NULL) {
  # If a code_list is available, sample from the exact valid values
  if (!is.null(code_list) && length(code_list) > 0) {
    codes <- vapply(code_list, function(x) as.character(x[["value"]]), character(1))
    return(sample(codes, size = n, replace = TRUE))
  }

  # Parse data type spec (e.g., "char(8)" -> type="char", length=8)
  parsed <- .parse_data_type(data_type)

  # Prefer explicit length from metadata JSON over parsed type length
  if (!is.null(meta_length) && !is.na(meta_length)) {
    parsed$length <- as.numeric(meta_length)
  }

  var_upper <- toupper(var_name)

  # Semantic fallback: if metadata suggests this is a date column but data_type
  # is empty/unknown, still generate YYYYMMDD strings.
  if (.looks_like_date_variable(var_name, data_type, description, usage_notes, meta_length)) {
    date_len <- ifelse(is.na(parsed$length), 8, parsed$length)
    return(.generate_char(var_upper, n, date_len, description, usage_notes, period_range))
  }

  switch(tolower(parsed$type),
    "char"      = .generate_char(var_upper, n, parsed$length, description, usage_notes, period_range),
    "varchar"   = .generate_varchar(var_upper, n, parsed$length),
    "character" = .generate_categorical(var_upper, n, description),
    "integer"   = .generate_integer(var_upper, n),
    "num"       = .generate_numeric(var_upper, n),
    "numeric"   = .generate_numeric(var_upper, n),
    "date"      = .generate_date(var_upper, n, period_range),
    "logical"   = sample(c(TRUE, FALSE), size = n, replace = TRUE),
    # Fallback
    .generate_categorical(var_upper, n, description)
  )
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
    # Normalize num -> numeric, int -> integer
    type <- switch(type, "num" = "num", "int" = "integer", type)
    length_match <- stringr::str_extract(spec, "\\d+")
    length <- as.numeric(length_match)
    list(type = type, length = length)
  } else if (grepl("^(char|varchar)", spec)) {
    type <- stringr::str_extract(spec, "^(char|varchar)")
    list(type = type, length = NA)
  } else {
    # Other types: integer, numeric, date, etc.
    list(type = spec, length = NA)
  }
}

#' Heuristic: detect date-like variables even when data_type is missing
#'
#' @keywords internal
.looks_like_date_variable <- function(var_name, data_type, description, usage_notes,
                                      meta_length = NULL) {
  var_upper <- toupper(var_name %||% "")
  txt <- toupper(paste(description %||% "", usage_notes %||% ""))
  dtype <- tolower(trimws(data_type %||% ""))

  name_or_text_date <- grepl("DATUM|DATE|AANVANG|AANV|BEGIN|EIND|EINDE|START", var_upper) ||
    grepl("DATUM|DATE|AANVANG|AANV|BEGIN|EIND|EINDE|START", txt)

  type_date <- grepl("^date", dtype) || grepl("char\\(8\\)", dtype)
  len_date <- !is.null(meta_length) && !is.na(meta_length) && as.numeric(meta_length) == 8

  isTRUE(name_or_text_date) && (isTRUE(type_date) || isTRUE(len_date) || dtype == "")
}

#' Generate Fixed-Length Character Data
#'
#' Checks description and usage_notes for semantic hints (e.g., "datum" = date column)
#'
#' @keywords internal
.generate_char <- function(var_upper, n, length, description = "", usage_notes = NULL,
                           period_range = NULL) {
  # For char columns, generate exactly the specified length
  if (is.na(length)) length <- 8  # default

  date_start <- period_range$start %||% as.Date("2010-01-01")
  date_end   <- period_range$end   %||% as.Date("2023-12-31")

  combined <- toupper(paste(description %||% "", usage_notes %||% ""))

  # Check both description and usage_notes for date semantics
  if (grepl("DATUM|DATE|BEGINDATUM|EINDDATUM|GEBOORTEDATUM|STERFDATUM", combined)) {
    dates <- seq(date_start, date_end, by = "day")
    return(format(sample(dates, size = n, replace = TRUE), "%Y%m%d"))
  }

  if (grepl("RINPERSOON", var_upper) && length == 9) {
    sprintf("%09d", sample(100000000:999999999, size = n, replace = TRUE))
  } else if (grepl("BEID", var_upper) && length == 8) {
    sprintf("%08d", sample(10000000:99999999, size = n, replace = TRUE))
  } else if (grepl("DATE|DATUM", var_upper) && length == 8) {
    dates <- seq(date_start, date_end, by = "day")
    format(sample(dates, size = n, replace = TRUE), "%Y%m%d")
  } else {
    replicate(n, paste0(sample(c(0:9, LETTERS), size = length, replace = TRUE), collapse = ""))
  }
}

#' Generate Variable-Length Character Data
#'
#' @keywords internal
.generate_varchar <- function(var_upper, n, length) {
  if (is.na(length)) length <- 100  # default max length
  # Generate variable-length strings up to max length
  replicate(n, {
    actual_length <- sample(1:length, size = 1)
    paste0(sample(c(0:9, letters), size = actual_length, replace = TRUE), collapse = "")
  })
}
#'
#' Generates common CBS categorical variables with realistic distributions
#'
#' @keywords internal
.generate_categorical <- function(var_upper, n, description = "") {
  if (grepl("GESLACHT", var_upper)) {
    sample(c("M", "V"), size = n, replace = TRUE, prob = c(0.51, 0.49))
  } else if (grepl("HERKOMST|AFKOMST|NATIONALITEIT", var_upper)) {
    sample(c("NL", "EU", "NIET-EU"), size = n, replace = TRUE,
           prob = c(0.85, 0.08, 0.07))
  } else if (grepl("BURGERLIJKE|CIVIEL", var_upper)) {
    sample(c("G", "G/P", "O", "W", "E"), size = n, replace = TRUE,
           prob = c(0.5, 0.02, 0.2, 0.25, 0.03))
  } else if (grepl("BEDRIJFSTAK|INDUSTRIE|SECTOR|SBI", var_upper)) {
    sample(c("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U"),
           size = n, replace = TRUE)
  } else if (grepl("POSITIE|STATUS|SOORT", var_upper)) {
    sample(c("E", "Z", "M", "V"), size = n, replace = TRUE)
  } else if (grepl("SCHOOL|ONDERWIJS|EDUCATIE", var_upper)) {
    sample(c("BO", "VSO", "VMBO", "HAVO", "VWO", "MBO", "HO"),
           size = n, replace = TRUE, prob = c(0.05, 0.05, 0.25, 0.15, 0.15, 0.25, 0.1))
  } else {
    # Generic categorical
    sample(c("A", "B", "C", "D"), size = n, replace = TRUE)
  }
}

#' Generate Integer Values
#'
#' Generates realistic integer values based on variable name patterns
#'
#' @keywords internal
.generate_integer <- function(var_upper, n) {
  if (grepl("GEBOORTEJAAR|BOORTE_JAAR|YEAR.*BIRTH|GEBOORTEDATUM", var_upper)) {
    sample(1940:2010, size = n, replace = TRUE)
  } else if (grepl("STERFJAAR|STERFDATUM|YEAR.*DEATH", var_upper)) {
    sample(1980:2020, size = n, replace = TRUE)
  } else if (grepl("JAAR$|YEAR$", var_upper)) {
    sample(2000:2024, size = n, replace = TRUE)
  } else if (grepl("MAAND|MONTH", var_upper)) {
    sample(1:12, size = n, replace = TRUE)
  } else if (grepl("DAG|DAY", var_upper)) {
    sample(1:31, size = n, replace = TRUE)
  } else if (grepl("POSTCODE|POSTAL", var_upper)) {
    sample(1000:9999, size = n, replace = TRUE)
  } else if (grepl("GEMEENTE|MUNICIPALITY", var_upper)) {
    sample(300:1999, size = n, replace = TRUE)
  } else if (grepl("AANTAL|COUNT|FREQUENCY|NUMBER", var_upper)) {
    sample(0:10, size = n, replace = TRUE)
  } else {
    sample(1:10000, size = n, replace = TRUE)
  }
}

#' Generate Numeric Values
#'
#' Generates realistic numeric values based on variable patterns
#' Uses log-normal distribution for income/financial variables
#'
#' @keywords internal
.generate_numeric <- function(var_upper, n) {
  if (grepl("LOON|SALARIS|INKOMEN|INKOMSTEN|INKOMST|WINST|OPBRENGST|VERMOGEN|BEZIT|UITKERING|UITKEER|TARIEF|LOONWAARDE", var_upper)) {
    # Income/financial: log-normal distribution (right-skewed)
    # meanlog ≈ 10.3, sdlog ≈ 0.8 gives realistic Dutch income distribution
    round(stats::rlnorm(n, meanlog = 10.3, sdlog = 0.8), 2)
  } else if (grepl("UREN|HOURS|DAGEN|WEEKS|MAANDEN|MONTHS", var_upper)) {
    # Hours/days: uniform in reasonable range
    round(stats::runif(n, min = 0, max = 60), 1)
  } else if (grepl("PERCENTAGE|PROCENT|RATE|FRACTIE", var_upper)) {
    # Percentages
    round(stats::runif(n, min = 0, max = 100), 1)
  } else {
    # Generic numeric
    round(stats::runif(n, min = 0, max = 100000), 2)
  }
}

#' Generate Date Values
#'
#' Generates dates in a reasonable range (typically 2000-2024 for CBS data)
#'
#' @keywords internal
.generate_date <- function(var_upper, n, period_range = NULL) {
  base_date  <- period_range$start %||% as.Date("2000-01-01")
  end_date   <- period_range$end   %||% as.Date("2024-12-31")
  date_range <- as.numeric(end_date - base_date)

  random_days <- sample(0:date_range, size = n, replace = TRUE)
  base_date + random_days
}

# Dataset-level constraint helpers ----------------------------------------

#' Parse Dataset Period Field into a Date Range
#'
#' Handles formats: "2022", "2010-2023", "2010 t/m 2023", "2022 IV", "2022 Q3"
#'
#' @return list(start = Date, end = Date)
#' @keywords internal
.parse_dataset_period <- function(period_str) {
  default <- list(start = as.Date("2000-01-01"), end = as.Date("2024-12-31"))

  if (is.null(period_str) || is.na(period_str) || nchar(trimws(period_str)) == 0) {
    return(default)
  }

  p <- trimws(period_str)

  # Single 4-digit year: "2022"
  if (grepl("^\\d{4}$", p)) {
    yr <- as.integer(p)
    return(list(start = as.Date(sprintf("%d-01-01", yr)),
                end   = as.Date(sprintf("%d-12-31", yr))))
  }

  # Year range with separator: "2010-2023", "2010 t/m 2023", "2010 tot 2023"
  if (grepl("^\\d{4}\\s*[-/]\\s*\\d{4}$|^\\d{4}\\s+(t/m|tot|to)\\s+\\d{4}$", p,
            ignore.case = TRUE)) {
    yrs <- as.integer(stringr::str_extract_all(p, "\\d{4}")[[1]])
    return(list(start = as.Date(sprintf("%d-01-01", yrs[1])),
                end   = as.Date(sprintf("%d-12-31", yrs[2]))))
  }

  # Year + Roman quarter: "2022 IV", "2022 III"
  if (grepl("^\\d{4}\\s+(I{1,3}V?|IV)$", p)) {
    yr    <- as.integer(stringr::str_extract(p, "^\\d{4}"))
    q_str <- toupper(trimws(sub("^\\d{4}\\s*", "", p)))
    q     <- switch(q_str, "I" = 1L, "II" = 2L, "III" = 3L, "IV" = 4L, 1L)
    q_end_days <- c("03-31", "06-30", "09-30", "12-31")
    return(list(
      start = as.Date(sprintf("%d-%02d-01", yr, (q - 1L) * 3L + 1L)),
      end   = as.Date(sprintf("%d-%s", yr, q_end_days[q]))
    ))
  }

  # Year + Q-quarter: "2022 Q4"
  if (grepl("^\\d{4}\\s+Q[1-4]$", p, ignore.case = TRUE)) {
    yr <- as.integer(stringr::str_extract(p, "^\\d{4}"))
    q  <- as.integer(stringr::str_extract(p, "[1-4]$"))
    q_end_days <- c("03-31", "06-30", "09-30", "12-31")
    return(list(
      start = as.Date(sprintf("%d-%02d-01", yr, (q - 1L) * 3L + 1L)),
      end   = as.Date(sprintf("%d-%s", yr, q_end_days[q]))
    ))
  }

  # Fallback: extract any years found
  yrs <- as.integer(stringr::str_extract_all(p, "\\d{4}")[[1]])
  yrs <- yrs[yrs >= 1900 & yrs <= 2100]
  if (length(yrs) >= 2) {
    return(list(start = as.Date(sprintf("%d-01-01", min(yrs))),
                end   = as.Date(sprintf("%d-12-31", max(yrs)))))
  } else if (length(yrs) == 1) {
    return(list(start = as.Date(sprintf("%d-01-01", yrs[1])),
                end   = as.Date(sprintf("%d-12-31", yrs[1]))))
  }

  default
}

#' Test Whether a Variable is a Date Column
#'
#' @keywords internal
.is_date_column <- function(var_name, var_meta) {
  var_upper <- toupper(var_name)
  name_is_date  <- grepl("DATUM|DATE", var_upper)
  type_is_date  <- grepl("^date", tolower(var_meta$data_type %||% ""))
  notes_is_date <- grepl("datum|date",
                         tolower(paste(var_meta$usage_notes %||% "",
                                       var_meta$description %||% "")))
  # char(8) whose length suggests YYYYMMDD
  length_8_char <- isTRUE(var_meta$meta_length == 8) ||
    grepl("char\\(8\\)", tolower(var_meta$data_type %||% ""))

  name_is_date || type_is_date || (notes_is_date && length_8_char)
}

#' Find Start/End Date Column Pairs
#'
#' For each column, checks whether its (uppercase) name contains any known
#' start-word. If so, tries substituting that word with each known end-word and
#' looks for a matching column. Longer words are tried first to avoid partial
#' matches (e.g. AANVANG is checked before AANV).
#'
#' Start words (by actual CBS catalogus frequency):
#'   AANVANG (87), AANV (214), BEGIN (66), START (57), OPNAME (20)
#' End words:
#'   EINDE (72), EIND (300)
#'
#' @return Named character vector: names = start cols, values = end cols
#' @keywords internal
.find_date_pairs <- function(col_names, variables) {
  # Longer patterns first — prevents partial substitution (AANVANG before AANV)
  START_WORDS <- c("AANVANG", "AANV", "BEGIN", "START", "OPNAME")
  END_WORDS   <- c("EINDE", "EIND")   # EINDE before EIND

  pairs    <- character(0)
  cu_names <- toupper(col_names)

  for (i in seq_along(col_names)) {
    start_col <- col_names[i]
    cu        <- cu_names[i]

    for (sw in START_WORDS) {
      if (!grepl(sw, cu, fixed = TRUE)) next
      for (ew in END_WORDS) {
        # Replace first occurrence of the start-word with the end-word
        candidate_cu <- sub(sw, ew, cu, fixed = TRUE)
        end_col      <- col_names[cu_names == candidate_cu]
        if (length(end_col) > 0) {
          pairs[start_col] <- end_col[1]
          break
        }
      }
      if (start_col %in% names(pairs)) break  # stop once a pair is found
    }
  }

  pairs
}

#' Apply Date Range Clamping and Start/End Pair Ordering
#'
#' Two passes:
#' 1. Clamp all date columns to within period_range
#' 2. Fix any start > end pairs: set end = start + random 1-365 days
#'
#' @keywords internal
.apply_date_constraints <- function(df, variables, period_range) {
  col_names  <- names(df)
  date_seq   <- seq(period_range$start, period_range$end, by = "day")

  # Pass 1: clamp dates to period range ----------------------------------
  for (cn in col_names) {
    var_meta <- variables[[cn]] %||% list()
    if (!.is_date_column(cn, var_meta)) next

    vals <- df[[cn]]

    if (is.character(vals) && length(vals) > 0 &&
        all(grepl("^\\d{8}$", na.omit(vals)))) {
      # YYYYMMDD string format
      dates     <- suppressWarnings(as.Date(vals, format = "%Y%m%d"))
      out_range <- !is.na(dates) & (dates < period_range$start | dates > period_range$end)
      if (any(out_range)) {
        df[[cn]][out_range] <- format(sample(date_seq, sum(out_range), replace = TRUE),
                                      "%Y%m%d")
      }

    } else if (inherits(vals, "Date")) {
      out_range <- !is.na(vals) & (vals < period_range$start | vals > period_range$end)
      if (any(out_range)) {
        df[[cn]][out_range] <- sample(date_seq, sum(out_range), replace = TRUE)
      }
    }
  }

  # Pass 2: enforce start <= end for known pairs -------------------------
  pairs <- .find_date_pairs(col_names, variables)
  for (start_col in names(pairs)) {
    end_col <- pairs[[start_col]]
    if (!end_col %in% col_names) next

    sv <- df[[start_col]]
    ev <- df[[end_col]]

    if (is.character(sv)) {
      sv_is_yyyymmdd <- all(grepl("^\\d{8}$", na.omit(sv)))
      ev_is_yyyymmdd <- all(grepl("^\\d{8}$", na.omit(ev)))
      if (!sv_is_yyyymmdd || !ev_is_yyyymmdd) next

      # Only compare rows where both sides are valid parseable dates.
      sv_date <- suppressWarnings(as.Date(sv, format = "%Y%m%d"))
      ev_date <- suppressWarnings(as.Date(ev, format = "%Y%m%d"))
      needs_fix <- !is.na(sv_date) & !is.na(ev_date) & sv_date > ev_date
      if (any(needs_fix)) {
        start_dates <- sv_date[needs_fix]
        offsets     <- sample(1:365, sum(needs_fix), replace = TRUE)
        new_ends    <- pmin(start_dates + offsets, period_range$end)
        df[[end_col]][needs_fix] <- format(new_ends, "%Y%m%d")
      }

    } else if (inherits(sv, "Date")) {
      needs_fix <- !is.na(sv) & !is.na(ev) & sv > ev
      if (any(needs_fix)) {
        offsets  <- sample(1:365, sum(needs_fix), replace = TRUE)
        new_ends <- pmin(sv[needs_fix] + offsets, period_range$end)
        df[[end_col]][needs_fix] <- new_ends
      }
    }
  }

  df
}

#' Warn if a Cross-Sectional Dataset Has Duplicate Entity Keys
#'
#' Detects cross-sectional datasets from unit_of_observation and warns when
#' the person key combination is not unique (n_records > n primary entities).
#'
#' @keywords internal
.apply_uniqueness_constraint <- function(df, metadata, key_cols) {
  if (length(key_cols) == 0) return(df)

  uob <- tolower(trimws(metadata$unit_of_observation %||% ""))
  if (nchar(uob) == 0) return(df)

  # Cross-sectional: unit is exactly "persoon" (not "per maand/jaar/baan/...")
  is_cross_sectional <-
    grepl("^persoon$", uob) ||
    (grepl("^persoon\\b", uob) &&
       !grepl("per |per-|maand|kwartaal|jaar|baan|uitkering|dienstverband|periode", uob))

  if (!is_cross_sectional) return(df)

  person_key_cols <- names(key_cols)[
    names(key_cols) %in% names(df) &
      sapply(names(key_cols), function(k) identical(key_cols[[k]], "person"))
  ]
  if (length(person_key_cols) == 0) return(df)

  n_dupes <- sum(duplicated(df[, person_key_cols, drop = FALSE]))
  if (n_dupes > 0) {
    cli::cli_warn(c(
      "!" = "{.val {metadata$dataset_name}} expects one row per person \\
             ({.field unit_of_observation}: {.val {metadata$unit_of_observation}})",
      " " = "{n_dupes} duplicate person key combination(s) found.",
      "i" = "Consider reducing {.arg n_records} or increasing {.arg primary_n}."
    ))
  }

  df
}
