test_that("export_data writes csv and rds and load_data reads back", {
  tmp <- tempfile("export-test-")
  dir.create(tmp)

  data <- tibble::tibble(A = c("x", NA_character_), B = c(1, 2))
  export_data(data, output_dir = tmp, dataset_name = "TEST", format = c("csv", "rds"))

  csv_path <- file.path(tmp, "TEST.csv")
  rds_path <- file.path(tmp, "TEST.rds")

  expect_true(file.exists(csv_path))
  expect_true(file.exists(rds_path))

  loaded_csv <- load_data(csv_path, format = "csv")
  loaded_rds <- load_data(rds_path, format = "rds")

  expect_equal(nrow(loaded_csv), 2)
  expect_equal(nrow(loaded_rds), 2)
})

test_that("export_datasets supports dataset subdirectories", {
  tmp <- tempfile("export-batch-")
  dir.create(tmp)

  datasets <- list(
    ASET = tibble::tibble(id = 1:2),
    BSET = tibble::tibble(id = 3:4)
  )

  export_datasets(
    datasets,
    output_dir = tmp,
    organize_by_dataset = TRUE,
    format = "csv",
    verbose = FALSE
  )

  expect_true(file.exists(file.path(tmp, "ASET", "ASET.csv")))
  expect_true(file.exists(file.path(tmp, "BSET", "BSET.csv")))
})

test_that("create_data_dictionary and summary_statistics treat NA as category", {
  data <- tibble::tibble(cat = c("x", NA_character_))

  dict <- create_data_dictionary(data)
  expect_equal(dict$n_missing, 1)
  expect_equal(dict$n_unique, 2)

  stats <- summary_statistics(data)
  expect_equal(stats$character$n, 2)
  expect_equal(stats$character$n_unique, 2)
  expect_equal(stats$character$top_freq, 1)
})

test_that("summary_statistics handles empty character columns without -Inf", {
  data <- data.frame(x = character(), stringsAsFactors = FALSE)
  stats <- summary_statistics(data)

  expect_equal(stats$character$n, 0)
  expect_equal(stats$character$n_unique, 0)
  expect_true(is.na(stats$character$top_freq))
  expect_true(is.na(stats$character$top_value))
})
