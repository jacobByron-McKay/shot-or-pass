fake_shots <- function(n = 400) {
  set.seed(7)
  d <- data.frame(
    distance = runif(n, 5, 30),
    y        = runif(n, 20, 60),
    defenders_in_cone = rpois(n, 1.5)
  )
  d$angle <- goal_angle(GOAL_X - d$distance, d$y)
  p <- plogis(-3 + 2 * d$angle - 0.4 * d$defenders_in_cone)
  d$goal <- rbinom(n, 1, p)
  d
}

test_that("the shot model recovers the sign of a known effect", {
  m <- fit_shot_value(fake_shots())
  expect_lt(coef(m)[["defenders_in_cone"]], 0)
  expect_gt(coef(m)[["angle"]], 0)
})

test_that("shot value falls as defenders fill the cone", {
  m <- fit_shot_value(fake_shots())
  clear    <- shot_value(m, distance = 12, angle = 0.6, defenders_in_cone = 0)
  crowded  <- shot_value(m, distance = 12, angle = 0.6, defenders_in_cone = 4)
  expect_gt(clear, crowded)
})

test_that("completion models behave the way their names claim", {
  expect_equal(completion_certain(30, 1), 1)
  expect_gt(completion_distance(5, 1), completion_distance(40, 1))
  expect_gt(completion_pressure(15, 12), completion_pressure(15, 1))
  for (f in COMPLETION_MODELS) {
    v <- f(c(3, 15, 45), c(1, 5, 12))
    expect_true(all(v >= 0 & v <= 1))
  }
})

test_that("the best alternative is zero when nobody is available", {
  m <- fit_shot_value(fake_shots())
  empty <- data.frame(x = numeric(0), y = numeric(0), distance = numeric(0),
                      angle = numeric(0), defenders_in_cone = numeric(0),
                      nearest_defender = numeric(0), pass_length = numeric(0))
  expect_equal(best_alternative(empty, m, completion_certain), 0)
})

test_that("the best alternative picks the best option, not the first", {
  m <- fit_shot_value(fake_shots())
  opts <- data.frame(
    x = c(105, 112), y = c(20, 40),
    distance = c(goal_distance(105, 20), goal_distance(112, 40)),
    angle    = c(goal_angle(105, 20), goal_angle(112, 40)),
    defenders_in_cone = c(3, 0),
    nearest_defender  = c(1, 8),
    pass_length = c(5, 6)
  )
  best <- best_alternative(opts, m, completion_certain)
  each <- shot_value(m, opts$distance, opts$angle, opts$defenders_in_cone)
  expect_equal(best, max(each))
  expect_gt(best, min(each))
})

test_that("a tighter option pool can only remove options, never add value", {
  m <- fit_shot_value(fake_shots())
  opts <- data.frame(
    x = c(95, 110), y = c(40, 40),
    distance = c(25, 10), angle = c(0.3, 0.8),
    defenders_in_cone = c(0, 0), nearest_defender = c(9, 9),
    pass_length = c(3, 20)
  )
  wide  <- best_alternative(pool_ahead(opts), m, completion_certain)
  tight <- best_alternative(pool_in_box(opts), m, completion_certain)
  expect_lte(tight, wide)
})
