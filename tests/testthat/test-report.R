test_that("numerals are pulled out of prose in all their usual forms", {
  txt <- "1,566 shots, 39.6% of them, an edge of -0.014 across 64 matches"
  expect_setequal(extract_numerals(txt),
                  c("1566", "39.6", "-0.014", "64"))
})

test_that("text quoting only approved figures passes", {
  approved <- approve(c(1566, 39.6))
  expect_silent(validate_numerals("1566 shots, 39.6% of them", approved))
})

test_that("a figure the analysis never produced is caught", {
  approved <- approve(c(1566, 39.6))
  expect_error(validate_numerals("1566 shots, 41.2% of them", approved),
               "41.2")
})

test_that("declared context values are allowed through", {
  approved <- approve(39.6)
  expect_error(validate_numerals("39.6% across 64 matches", approved))
  expect_silent(validate_numerals("39.6% across 64 matches", approved,
                                  context = 64))
})

test_that("the gate reports every offender, not just the first", {
  bad <- validate_numerals("7 and 8 and 9", approve(9), strict = FALSE)
  expect_setequal(bad, c(7, 8))
})

test_that("rounding a value registers the forms prose actually quotes", {
  a <- approve(39.61538)
  expect_true(39.6 %in% a)
  expect_true(40 %in% a)
  expect_silent(validate_numerals("39.6% of shots", a))
})
