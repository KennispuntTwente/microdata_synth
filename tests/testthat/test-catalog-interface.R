test_that("catalog interface functions query expected metadata", {
  db_file <- tempfile("catalog-", fileext = ".sqlite")
  create_test_catalog_db(db_file)

  with_mocked_binding(".get_catalogus_conn", function(db_path = NULL) {
    DBI::dbConnect(RSQLite::SQLite(), db_file)
  }, {
    datasets <- list_datasets()
    expect_gte(nrow(datasets), 2)
    expect_true(all(c("name", "description") %in% names(datasets)))

    vars <- list_variables("SECMBUS")
    expect_true("RINPERSOON" %in% vars$name)

    meta <- get_dataset_metadata("SECMBUS")
    expect_equal(meta$dataset_name, "SECMBUS")
    expect_true("RINPERSOONS" %in% names(meta$variables))
    expect_equal(meta$variables$RINPERSOONS$meta_length, 1)
    expect_true(length(meta$variables$RINPERSOONS$code_list) >= 1)

    keys <- get_dataset_keys("SECMBUS")
    expect_true(all(c("RINPERSOON", "RINPERSOONS") %in% keys$name))

    join_keys <- get_join_keys()
    expect_true(any(join_keys$key_name == "RINPERSOON"))
    dataset_join_keys <- get_join_keys("sEcMbUs")
    expect_true(all(c("RINPERSOON", "RINPERSOONS") %in% dataset_join_keys$key_name))

    key_overview <- get_key_type_overview("sEcMbUs")
    expect_true(any(key_overview$key_type == "person"))

    catalog_status <- check_catalogus_status("sEcMbUs")
    expect_equal(nrow(catalog_status), 1)
    expect_equal(catalog_status$name, "SECMBUS")

    by_type <- find_datasets_by_key_type("person")
    expect_true("SECMBUS" %in% by_type$name)

    stats <- get_catalogus_stats()
    expect_gte(stats$n_datasets, 2)
    expect_gte(stats$n_variables, 2)
  })
})

test_that("find_linkable_datasets returns datasets for a key name", {
  db_file <- tempfile("catalog-", fileext = ".sqlite")
  create_test_catalog_db(db_file)

  with_mocked_binding(".get_catalogus_conn", function(db_path = NULL) {
    DBI::dbConnect(RSQLite::SQLite(), db_file)
  }, {
    out <- find_linkable_datasets("RINPERSOON")
    expect_true(is.data.frame(out))
    expect_true("SECMBUS" %in% out$name)
  })
})
