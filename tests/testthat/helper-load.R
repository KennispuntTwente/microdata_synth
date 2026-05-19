find_project_root <- function(start = getwd(), marker = file.path("R", "main.R")) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  for (i in 0:6) {
    candidate <- normalizePath(file.path(current, paste(rep("..", i), collapse = "/")),
                               winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(candidate, marker))) {
      return(candidate)
    }
  }
  stop("Could not locate project root containing R/main.R")
}

project_root <- find_project_root()
setwd(project_root)
source(file.path(project_root, "R", "main.R"))

with_mocked_binding <- function(name, replacement, code, env = globalenv()) {
  had_original <- exists(name, envir = env, inherits = FALSE)
  if (had_original) {
    original <- get(name, envir = env, inherits = FALSE)
  }

  assign(name, replacement, envir = env)
  on.exit({
    if (had_original) {
      assign(name, original, envir = env)
    } else if (exists(name, envir = env, inherits = FALSE)) {
      rm(list = name, envir = env)
    }
  }, add = TRUE)

  eval(substitute(code), envir = parent.frame())
}

create_test_catalog_db <- function(path) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbExecute(conn, "
    CREATE TABLE datasets (
      id INTEGER PRIMARY KEY,
      name TEXT,
      full_name TEXT,
      description TEXT,
      unit_of_observation TEXT,
      frequency TEXT,
      period TEXT,
      detail_last_scraped TEXT,
      pdf_last_parsed TEXT,
      pdf_parsed INTEGER
    )
  ")

  DBI::dbExecute(conn, "
    CREATE TABLE variables (
      id INTEGER PRIMARY KEY,
      dataset_id INTEGER,
      name TEXT,
      description TEXT,
      data_type TEXT,
      is_key INTEGER,
      key_type TEXT,
      metadata TEXT
    )
  ")

  DBI::dbExecute(conn, "
    CREATE TABLE join_keys (
      key_name TEXT,
      key_type TEXT,
      description TEXT
    )
  ")

  DBI::dbExecute(conn, "CREATE TABLE categories (id INTEGER PRIMARY KEY)")

  DBI::dbExecute(conn, "
    INSERT INTO datasets (
      id, name, full_name, description, unit_of_observation, frequency, period,
      detail_last_scraped, pdf_last_parsed, pdf_parsed
    ) VALUES
      (1, 'SECMBUS', 'SECM Full', 'Security dataset', 'persoon', 'M', '2020-2021', '2024-01-01', '2024-01-02', 1),
      (2, 'SPOLISBUS', 'SPOLIS Full', 'Polis dataset', 'persoon', 'M', '2021', '2024-01-01', '2024-01-02', 1)
  ")

  rinpersons_meta <- jsonlite::toJSON(list(
    usage_notes = "Source code",
    code_list = list(list(value = "R", label = "RNI"), list(value = "S", label = "SOFI")),
    length = 1
  ), auto_unbox = TRUE)

  DBI::dbExecute(conn, "
    INSERT INTO variables (id, dataset_id, name, description, data_type, is_key, key_type, metadata)
    VALUES
      (1, 1, 'RINPERSOON', 'Person id', 'char(9)', 1, 'person', NULL),
      (2, 1, 'RINPERSOONS', 'Person source', 'char(1)', 1, 'person', ?),
      (3, 1, 'WAARDE', 'Amount', 'num(2)', 0, NULL, NULL),
      (4, 2, 'RINPERSOON', 'Person id', 'char(9)', 1, 'person', NULL),
      (5, 2, 'RINPERSOONS', 'Person source', 'char(1)', 1, 'person', ?),
      (6, 2, 'AANVANGDATUM', 'Start datum', 'char(8)', 0, NULL, NULL),
      (7, 2, 'EINDDATUM', 'Eind datum', 'char(8)', 0, NULL, NULL)
  ", params = list(rinpersons_meta, rinpersons_meta))

  DBI::dbExecute(conn, "
    INSERT INTO join_keys (key_name, key_type, description)
    VALUES ('RINPERSOON', 'person', 'Person key'), ('RINPERSOONS', 'person', 'Person source')
  ")

  DBI::dbExecute(conn, "INSERT INTO categories (id) VALUES (1), (2)")

  invisible(path)
}
