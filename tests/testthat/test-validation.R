test_that("validate_data reports missing columns and type issues", {
  metadata <- list(
    dataset_name = "TESTDS",
    full_name = "Test dataset",
    variables = list(
      A = list(data_type = "integer"),
      B = list(data_type = "char(1)")
    )
  )

  data <- tibble::tibble(A = c("x", "y"))
  result <- validate_data(data, metadata, verbose = FALSE)

  expect_false(result$valid)
  expect_true("B" %in% result$missing_columns)
  expect_true(any(grepl("A: expected integer", result$issues)))
})

test_that("check_referential_integrity includes mandatory tuple-level checks", {
  datasets <- list(
    PARENT = data.frame(
      RINPERSOON = c("1", "2"),
      RINPERSOONS = c("A", "B"),
      stringsAsFactors = FALSE
    ),
    CHILD = data.frame(
      RINPERSOON = c("1", "2"),
      RINPERSOONS = c("B", "A"),
      stringsAsFactors = FALSE
    )
  )

  out <- check_referential_integrity(
    datasets = datasets,
    primary_dataset = "PARENT",
    key_cols = c("RINPERSOON", "RINPERSOONS"),
    verbose = FALSE
  )

  tuple_row <- out[out$key_column == "RINPERSOON + RINPERSOONS", ]

  expect_equal(nrow(tuple_row), 1)
  expect_false(tuple_row$integrity_ok)
  expect_equal(tuple_row$n_orphaned, 2)
  expect_identical(tuple_row$note, "tuple-level check")
})
