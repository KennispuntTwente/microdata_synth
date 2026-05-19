test_that("generate_synthetic_data respects metadata code list and row count", {
  fake_meta <- list(
    dataset_name = "FAKE",
    full_name = "Fake",
    description = "Fake dataset",
    unit_of_observation = "persoon",
    frequency = "M",
    period = "2022",
    variables = list(
      RINPERSOON = list(
        name = "RINPERSOON", description = "Person", data_type = "char(9)",
        is_key = TRUE, key_type = "person", usage_notes = NULL,
        code_list = NULL, meta_length = 9
      ),
      RINPERSOONS = list(
        name = "RINPERSOONS", description = "Source", data_type = "char(1)",
        is_key = TRUE, key_type = "person", usage_notes = NULL,
        code_list = list(list(value = "R"), list(value = "S")), meta_length = 1
      ),
      WAARDE = list(
        name = "WAARDE", description = "Amount", data_type = "num(2)",
        is_key = FALSE, key_type = NULL, usage_notes = NULL,
        code_list = NULL, meta_length = 2
      )
    )
  )

  with_mocked_binding("get_dataset_metadata", function(dataset_name) fake_meta, {
    out <- generate_synthetic_data("FAKE", n_records = 50, seed = 1)

    expect_equal(nrow(out), 50)
    expect_true(all(out$RINPERSOONS %in% c("R", "S")))
    expect_true(is.numeric(out$WAARDE))
  })
})

test_that("generate_synthetic_data enforces date ordering within period", {
  fake_meta <- list(
    dataset_name = "DATESET",
    full_name = "Date set",
    description = "Date dataset",
    unit_of_observation = "persoon",
    frequency = "M",
    period = "2022",
    variables = list(
      RINPERSOON = list(
        name = "RINPERSOON", description = "Person", data_type = "char(9)",
        is_key = TRUE, key_type = "person", usage_notes = NULL,
        code_list = NULL, meta_length = 9
      ),
      AANVANGDATUM = list(
        name = "AANVANGDATUM", description = "Start datum", data_type = "char(8)",
        is_key = FALSE, key_type = NULL, usage_notes = NULL,
        code_list = NULL, meta_length = 8
      ),
      EINDDATUM = list(
        name = "EINDDATUM", description = "Eind datum", data_type = "char(8)",
        is_key = FALSE, key_type = NULL, usage_notes = NULL,
        code_list = NULL, meta_length = 8
      )
    )
  )

  with_mocked_binding("get_dataset_metadata", function(dataset_name) fake_meta, {
    out <- generate_synthetic_data("DATESET", n_records = 80, seed = 2)

    start_dates <- as.Date(out$AANVANGDATUM, format = "%Y%m%d")
    end_dates <- as.Date(out$EINDDATUM, format = "%Y%m%d")

    expect_true(all(!is.na(start_dates)))
    expect_true(all(!is.na(end_dates)))
    expect_true(all(start_dates <= end_dates))
    expect_true(all(format(start_dates, "%Y") == "2022"))
    expect_true(all(format(end_dates, "%Y") == "2022"))
  })
})

test_that("generate_linked_datasets preserves composite key tuples", {
  parent_meta <- list(
    dataset_name = "PARENT",
    full_name = "Parent",
    description = "Parent dataset",
    unit_of_observation = "persoon",
    frequency = "M",
    period = "2022",
    variables = list(
      RINPERSOON = list(name = "RINPERSOON", description = "", data_type = "char(9)", is_key = TRUE, key_type = "person", usage_notes = NULL, code_list = NULL, meta_length = 9),
      RINPERSOONS = list(name = "RINPERSOONS", description = "", data_type = "char(1)", is_key = TRUE, key_type = "person", usage_notes = NULL, code_list = list(list(value = "R"), list(value = "S")), meta_length = 1)
    )
  )

  child_meta <- parent_meta
  child_meta$dataset_name <- "CHILD"

  with_mocked_binding("get_dataset_metadata", function(dataset_name) {
    if (identical(dataset_name, "PARENT")) parent_meta else child_meta
  }, {
    out <- generate_linked_datasets(
      dataset_names = c("PARENT", "CHILD"),
      primary_dataset = "PARENT",
      n_records = list(PARENT = 30, CHILD = 30),
      seed = 42
    )

    parent <- out$PARENT
    child <- out$CHILD

    parent_tuple <- paste(parent$RINPERSOON, parent$RINPERSOONS, sep = "|")
    child_tuple <- paste(child$RINPERSOON, child$RINPERSOONS, sep = "|")

    expect_true(all(child_tuple %in% parent_tuple))
  })
})
