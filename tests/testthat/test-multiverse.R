test_that("every combination of choices is generated exactly once", {
  choices <- list(a = list(one = 1, two = 2),
                  b = list(x = "x", y = "y", z = "z"))
  spec <- specifications(choices)
  expect_equal(nrow(spec), 6)
  expect_equal(nrow(unique(spec)), 6)
  expect_setequal(names(spec), c("a", "b"))
})

test_that("the harness passes the selected values through, not their names", {
  choices <- list(f = list(double = function(x) x * 2,
                           treble = function(x) x * 3))
  mv <- multiverse(choices, function(pick) c(out = pick$f(10)), verbose = FALSE)
  expect_setequal(mv$out, c(20, 30))
})

test_that("sensitivity ranks the decision that moves the outcome most", {
  mv <- data.frame(
    big   = rep(c("lo", "hi"), each = 4),
    small = rep(c("lo", "hi"), times = 4),
    value = c(1, 1.1, 1, 1.1, 9, 9.1, 9, 9.1)
  )
  s <- sensitivity(mv, "value", decisions = c("big", "small"))
  expect_equal(s$decision[1], "big")
  expect_gt(s$spread[1], s$spread[2])
})

test_that("a decision that changes nothing has no spread", {
  mv <- data.frame(inert = rep(c("a", "b"), each = 2), value = c(5, 5, 5, 5))
  s <- sensitivity(mv, "value", decisions = "inert")
  expect_equal(s$spread, 0)
})

test_that("the bootstrap interval brackets the observed statistic", {
  set.seed(42)
  x <- rnorm(500, mean = 10)
  b <- bootstrap_spread(x, mean, n = 500)
  expect_lt(b$low, 10)
  expect_gt(b$high, 10)
  expect_equal(b$width, b$high - b$low)
})

test_that("the bootstrap accepts a data frame and resamples its rows", {
  set.seed(1)
  d <- data.frame(v = c(rep(0, 50), rep(1, 50)))
  b <- bootstrap_spread(d, function(x) mean(x$v), n = 300)
  expect_true(b$low > 0.3 && b$high < 0.7)
})
