test_that("search_datasets dispatches to fuzzy mode", {
  with_mocked_binding("search_datasets_fuzzy", function(pattern, limit = 10) {
    tibble::tibble(mode = "fuzzy", pattern = pattern, limit = limit)
  }, {
    with_mocked_binding("search_datasets_fts", function(keyword, limit = 10) {
      tibble::tibble(mode = "fts", keyword = keyword, limit = limit)
    }, {
      out <- search_datasets("polis", mode = "fuzzy", limit = 3)
      expect_equal(out$mode[[1]], "fuzzy")
      expect_equal(out$limit[[1]], 3)
    })
  })
})

test_that("search_datasets dispatches to fts mode", {
  with_mocked_binding("search_datasets_fts", function(keyword, limit = 10) {
    tibble::tibble(mode = "fts", keyword = keyword, limit = limit)
  }, {
    out <- search_datasets("polis", mode = "fts", limit = 5)
    expect_equal(out$mode[[1]], "fts")
    expect_equal(out$limit[[1]], 5)
  })
})

test_that("search_datasets auto prefers fts and falls back to fuzzy", {
  with_mocked_binding("search_datasets_fts", function(keyword, limit = 10) {
    tibble::tibble(mode = "fts", keyword = keyword)
  }, {
    with_mocked_binding("search_datasets_fuzzy", function(pattern, limit = 10) {
      tibble::tibble(mode = "fuzzy", pattern = pattern)
    }, {
      out <- search_datasets("polis", mode = "auto", limit = 2)
      expect_equal(out$mode[[1]], "fts")
    })
  })

  with_mocked_binding("search_datasets_fts", function(keyword, limit = 10) {
    stop("FTS unavailable")
  }, {
    with_mocked_binding("search_datasets_fuzzy", function(pattern, limit = 10) {
      tibble::tibble(mode = "fuzzy", pattern = pattern)
    }, {
      out <- search_datasets("polis", mode = "auto", limit = 2)
      expect_equal(out$mode[[1]], "fuzzy")
    })
  })

  with_mocked_binding("search_datasets_fts", function(keyword, limit = 10) {
    tibble::tibble()
  }, {
    with_mocked_binding("search_datasets_fuzzy", function(pattern, limit = 10) {
      tibble::tibble(mode = "fuzzy", pattern = pattern)
    }, {
      out <- search_datasets("polis", mode = "auto", limit = 2)
      expect_equal(out$mode[[1]], "fuzzy")
    })
  })
})
