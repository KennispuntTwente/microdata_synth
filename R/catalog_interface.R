# Catalog Interface -------------------------------------------------------
# Functions to query the microdata_catalogus database and extract metadata

#' Connect to the Microdata Catalogus Database
#'
#' @param db_path Path to the catalogus.db file. If NULL, looks in standard location.
#'
#' @return A database connection object (RSQLite)
#'
#' @keywords internal
.get_catalogus_conn <- function(db_path = NULL) {
  if (is.null(db_path)) {
    db_path <- "../microdata_catalogus/data/sqlite/catalogus.db"
  }

  if (!file.exists(db_path)) {
    cli::cli_abort(c(
      "Catalogus database not found at {.path {db_path}}",
      "i" = "Make sure microdata_catalogus is cloned at {.path ../microdata_catalogus/}",
      "i" = "Run: {.code uv run python scripts/catalog.py update} to generate the database"
    ))
  }

  DBI::dbConnect(RSQLite::SQLite(), db_path)
}

#' List All Available Datasets
#'
#' @return A tibble with dataset names, descriptions, and metadata
#'
#' @export
list_datasets <- function() {
  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  result <- DBI::dbGetQuery(conn, "
    SELECT
      id,
      name,
      full_name,
      description,
      unit_of_observation,
      frequency,
      period
    FROM datasets
    ORDER BY name
  ")

  tibble::as_tibble(result)
}

#' List Variables in a Dataset
#'
#' @param dataset_name Name of the dataset (e.g. 'GBAPERSOONTAB')
#'
#' @export
list_variables <- function(dataset_name) {
  stopifnot(is.character(dataset_name), length(dataset_name) == 1)

  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  result <- DBI::dbGetQuery(
    conn,
    "
    SELECT
      v.id,
      v.name,
      v.description,
      v.data_type,
      v.is_key,
      v.key_type,
      d.name AS dataset_name
    FROM variables v
    JOIN datasets d ON v.dataset_id = d.id
    WHERE UPPER(d.name) = UPPER(?)
    ORDER BY v.name
    ",
    params = list(dataset_name)
  )

  if (nrow(result) == 0) {
    cli::cli_warn("No variables found for dataset {.val {dataset_name}}")
    return(tibble::tibble())
  }

  tibble::as_tibble(result)
}

#' Get Full Metadata for a Dataset
#'
#' Returns all metadata needed to generate synthetic data: variable names, types,
#' data ranges, valid categories, and join key information.
#'
#' @param dataset_name Name of the dataset (e.g. 'GBAPERSOONTAB')
#'
#' @return A nested list with dataset info and variable metadata
#'
#' @export
get_dataset_metadata <- function(dataset_name) {
  stopifnot(is.character(dataset_name), length(dataset_name) == 1)

  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  # Get dataset info
  dataset_info <- DBI::dbGetQuery(
    conn,
    "
    SELECT
      id,
      name,
      full_name,
      description,
      unit_of_observation,
      frequency,
      period
    FROM datasets
    WHERE UPPER(name) = UPPER(?)
    ",
    params = list(dataset_name)
  )

  if (nrow(dataset_info) == 0) {
    cli::cli_abort("Dataset {.val {dataset_name}} not found in catalogus")
  }

  dataset_id <- dataset_info$id[1]

  # Get variables (including metadata JSON column)
  variables <- DBI::dbGetQuery(
    conn,
    "
    SELECT
      name,
      description,
      data_type,
      is_key,
      key_type,
      metadata
    FROM variables
    WHERE dataset_id = ?
    ORDER BY name
    ",
    params = list(dataset_id)
  )

  variables <- tibble::as_tibble(variables)

  # Helper: parse a single metadata JSON string into a list
  .parse_var_metadata <- function(json_str) {
    if (is.na(json_str) || nchar(trimws(json_str)) == 0) {
      return(list(usage_notes = NULL, code_list = NULL, length = NULL))
    }
    parsed <- tryCatch(
      jsonlite::fromJSON(json_str, simplifyVector = FALSE),
      error = function(e) list()
    )
    list(
      usage_notes = parsed[["usage_notes"]],
      code_list   = parsed[["code_list"]],   # list of {value, label} or NULL
      length      = parsed[["length"]]
    )
  }

  # Convert to nested structure for easier use
  var_list <- purrr::map(
    seq_len(nrow(variables)),
    ~ {
      meta_parsed <- .parse_var_metadata(variables$metadata[.x])
      list(
        name        = variables$name[.x],
        description = variables$description[.x],
        data_type   = tolower(variables$data_type[.x]),
        is_key      = as.logical(variables$is_key[.x]),
        key_type    = variables$key_type[.x],
        usage_notes = meta_parsed$usage_notes,
        code_list   = meta_parsed$code_list,   # NULL or list of {value, label}
        meta_length = meta_parsed$length       # explicit length from metadata
      )
    }
  ) |>
    rlang::set_names(variables$name)

  list(
    dataset_name = dataset_info$name[1],
    full_name = dataset_info$full_name[1],
    description = dataset_info$description[1],
    unit_of_observation = dataset_info$unit_of_observation[1],
    frequency = dataset_info$frequency[1],
    period = dataset_info$period[1],
    variables = var_list
  )
}

#' Get Join Key Information
#'
#' Returns linking keys based on actual usage in `variables`.
#' Optionally includes dictionary-only keys from `join_keys` with zero usage.
#'
#' @param dataset_name Optional dataset filter.
#' @param include_unused If TRUE, include keys from `join_keys` that currently have zero usage.
#'
#' @return A tibble with join key metadata including usage counts
#'
#' @export
get_join_keys <- function(dataset_name = NULL, include_unused = FALSE) {
  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  where_clause <- if (is.null(dataset_name)) "" else " AND d.name = ?"

  usage_query <- paste0(
    "
    WITH key_usage AS (
      SELECT
        UPPER(v.name) AS key_name,
        MAX(COALESCE(NULLIF(v.key_type, ''), 'unknown')) AS key_type,
        COUNT(DISTINCT v.dataset_id) AS n_datasets
      FROM variables v
      JOIN datasets d ON d.id = v.dataset_id
      WHERE v.is_key = 1",
    where_clause,
    "
      GROUP BY UPPER(v.name)
    )
    SELECT
      ku.key_name,
      COALESCE(jk.key_type, ku.key_type, 'unknown') AS key_type,
      COALESCE(jk.description, '') AS description,
      ku.n_datasets
    FROM key_usage ku
    LEFT JOIN join_keys jk ON UPPER(jk.key_name) = ku.key_name
    "
  )

  if (is.null(dataset_name)) {
    result <- DBI::dbGetQuery(conn, usage_query)
  } else {
    result <- DBI::dbGetQuery(conn, usage_query, params = list(dataset_name))
  }

  if (isTRUE(include_unused)) {
    unused_query <- "
      SELECT
        UPPER(jk.key_name) AS key_name,
        jk.key_type,
        jk.description,
        0 AS n_datasets
      FROM join_keys jk
      WHERE UPPER(jk.key_name) NOT IN (
        SELECT DISTINCT UPPER(v.name)
        FROM variables v
        WHERE v.is_key = 1
      )
    "
    result <- dplyr::bind_rows(result, DBI::dbGetQuery(conn, unused_query))
  }

  result <- result |>
    tibble::as_tibble() |>
    dplyr::arrange(dplyr::desc(n_datasets), key_type, key_name)

  result
}

#' Get Key Type Overview
#'
#' Returns accurate counts by key type from `variables`.
#' `n_datasets` counts distinct datasets per key type.
#'
#' @param dataset_name Optional dataset filter.
#'
#' @return A tibble with key_type, n_keys, n_datasets
#'
#' @export
get_key_type_overview <- function(dataset_name = NULL) {
  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  where_clause <- if (is.null(dataset_name)) "" else " AND d.name = ?"

  query <- paste0(
    "
    SELECT
      COALESCE(NULLIF(v.key_type, ''), 'unknown') AS key_type,
      COUNT(DISTINCT UPPER(v.name)) AS n_keys,
      COUNT(DISTINCT v.dataset_id) AS n_datasets
    FROM variables v
    JOIN datasets d ON d.id = v.dataset_id
    WHERE v.is_key = 1",
    where_clause,
    "
    GROUP BY COALESCE(NULLIF(v.key_type, ''), 'unknown')
    ORDER BY n_datasets DESC, key_type
    "
  )

  result <- if (is.null(dataset_name)) {
    DBI::dbGetQuery(conn, query)
  } else {
    DBI::dbGetQuery(conn, query, params = list(dataset_name))
  }

  tibble::as_tibble(result)
}

#' Get Keys Used in a Dataset
#'
#' Lists all linking/key columns in a specific dataset with their types
#'
#' @param dataset_name Name of the dataset
#'
#' @return A tibble with key columns in the dataset
#'
#' @export
get_dataset_keys <- function(dataset_name) {
  stopifnot(is.character(dataset_name), length(dataset_name) == 1)

  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  result <- DBI::dbGetQuery(
    conn,
    "
    SELECT
      v.name,
      v.key_type,
      v.description,
      d.name AS dataset_name
    FROM variables v
    JOIN datasets d ON v.dataset_id = d.id
    WHERE UPPER(d.name) = UPPER(?) AND v.is_key = 1
    ORDER BY v.name
    ",
    params = list(dataset_name)
  )

  if (nrow(result) == 0) {
    cli::cli_warn("No key columns found in dataset {.val {dataset_name}}")
    return(tibble::tibble())
  }

  tibble::as_tibble(result)
}

#' Find Datasets by Key Type
#'
#' Find all datasets that use a specific type of linking key
#'
#' @param key_type Type of key: "person", "business", "job", "household", "object", "address", "education"
#'
#' @return A tibble with datasets using that key type
#'
#' @export
find_datasets_by_key_type <- function(key_type) {
  stopifnot(is.character(key_type), length(key_type) == 1)

  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  result <- DBI::dbGetQuery(
    conn,
    "
    SELECT DISTINCT
      d.name,
      d.full_name,
      d.description,
      COUNT(v.id) as n_keys_of_type
    FROM datasets d
    JOIN variables v ON v.dataset_id = d.id
    WHERE v.is_key = 1 AND v.key_type = ?
    GROUP BY d.id, d.name, d.full_name, d.description
    ORDER BY n_keys_of_type DESC, d.name
    ",
    params = list(key_type)
  )

  if (nrow(result) == 0) {
    cli::cli_warn("No datasets found using key type {.val {key_type}}")
    return(tibble::tibble())
  }

  tibble::as_tibble(result)
}

#' Check Dataset Status
#'
#' Shows last update times and whether documentation PDFs have been parsed
#'
#' @param dataset_name Optional dataset name to check specific dataset
#'
#' @return A tibble with update status
#'
#' @export
check_catalogus_status <- function(dataset_name = NULL) {
  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  query <- "
    SELECT
      name,
      detail_last_scraped,
      pdf_last_parsed,
      pdf_parsed
    FROM datasets
    ORDER BY name
  "

  if (!is.null(dataset_name)) {
    query <- stringr::str_replace(query, "ORDER BY", "WHERE name = ? ORDER BY")
    result <- DBI::dbGetQuery(conn, query, params = list(dataset_name))
  } else {
    result <- DBI::dbGetQuery(conn, query)
  }

  tibble::as_tibble(result)
}

#' Search Datasets by Full-Text Search
#'
#' Searches dataset names and descriptions using SQLite FTS.
#'
#' @param keyword Search term
#' @param limit Maximum number of results
#'
#' @return A tibble with matching datasets
#'
#' @export
search_datasets_fts <- function(keyword, limit = 10) {
  stopifnot(is.character(keyword), length(keyword) == 1)

  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  result <- DBI::dbGetQuery(
    conn,
    "
    SELECT
      d.name,
      d.full_name,
      d.description,
      rank
    FROM datasets_fts
    JOIN datasets d ON datasets_fts.rowid = d.id
    WHERE datasets_fts MATCH ?
    ORDER BY rank
    LIMIT ?
    ",
    params = list(keyword, limit)
  )

  tibble::as_tibble(result)
}

#' Get Dataset Statistics
#'
#' Returns counts and metadata about the database contents
#'
#' @return A list with database statistics
#'
#' @export
get_catalogus_stats <- function() {
  conn <- .get_catalogus_conn()
  on.exit(DBI::dbDisconnect(conn))

  n_datasets <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM datasets")$n
  n_variables <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM variables")$n
  n_categories <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM categories")$n

  list(
    n_datasets = n_datasets,
    n_variables = n_variables,
    n_categories = n_categories
  )
}
