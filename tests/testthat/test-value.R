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

test_that("the measured completion model rewards space and punishes a blocked lane", {
  expect_gt(completion_tracking(10, 6, 0), completion_tracking(10, 1, 0))
  expect_gt(completion_tracking(10, 6, 0), completion_tracking(10, 6, 2))
  expect_gt(completion_tracking(5, 6, 0), completion_tracking(25, 6, 0))
  v <- completion_tracking(c(3, 15, 45), c(1, 5, 12), c(0, 1, 3))
  expect_true(all(v >= 0 & v <= 1))
})

test_that("the cutback pool adds the teammates behind the ball and nothing else", {
  ahead  <- data.frame(x = 112, y = 40, distance = 8, angle = 0.9, defenders_in_cone = 1,
                       nearest_defender = 3, pass_length = 4, lane_blockers = 0,
                       offside = FALSE, open_goal = 0.8)
  behind <- ahead
  behind$x <- 105
  shot <- data.frame(x = 108)
  shot$behind <- I(list(behind))
  expect_equal(nrow(pool_with_cutbacks(ahead, shot)), 2)
  expect_equal(nrow(pool_ahead(ahead, shot)), 1)
})

test_that("the offside rule can only remove options, never add value", {
  m <- fit_shot_value(fake_shots())
  opts <- data.frame(x = c(110, 116), y = c(40, 40), distance = c(10, 4),
                     angle = c(0.8, 1.6), defenders_in_cone = c(0, 0),
                     nearest_defender = c(5, 5), pass_length = c(4, 8),
                     lane_blockers = c(0, 0), offside = c(FALSE, TRUE))
  with_rule    <- best_alternative(opts, m, completion_certain, offside_rule = TRUE)
  without_rule <- best_alternative(opts, m, completion_certain, offside_rule = FALSE)
  expect_lte(with_rule, without_rule)
})

test_that("a miss is still worth something, more so close to goal", {
  expect_gt(AFTERMATH$shot(5), AFTERMATH$shot(28))
  expect_true(all(AFTERMATH$shot(c(1, 12, 40)) > 0))
  expect_lt(AFTERMATH$failed_pass, AFTERMATH$shot(15))
})

test_that("a keeper caught off the line makes the same shot worth more", {
  d <- fake_shots(800)
  set.seed(11)
  d$keeper_x <- ifelse(runif(nrow(d)) < 0.1, NA, 120 - rexp(nrow(d), 1 / 2.5))
  off <- ifelse(is.na(d$keeper_x), 2.4, 120 - d$keeper_x)
  d$goal <- rbinom(nrow(d), 1, plogis(-3 + 2 * d$angle - 0.4 * d$defenders_in_cone + 0.3 * off))
  m <- fit_shot_value(d, keeper = TRUE)
  on_line <- shot_value(m, 12, 0.6, 0, keeper_x = 119)
  caught  <- shot_value(m, 12, 0.6, 0, keeper_x = 112)
  unseen  <- shot_value(m, 12, 0.6, 0, keeper_x = NA)
  expect_gt(caught, on_line)
  expect_true(is.finite(unseen))
})

test_that("a receiver with room loses some of it by the time the ball arrives", {
  expect_lt(closing_in(9, 20), 9)
  expect_gt(closing_in(9, 20), closing_in(4, 20))
  expect_lt(closing_in(9, 30), closing_in(9, 5))
  expect_lte(max(closing_in(c(1, 50, 99), 10)), SPACE_CAP)
})

test_that("an average corner reproduces the flat aftermath values exactly", {
  flat <- c(0.0455, 0.0235, 0.0226, 0.0101, 0.0034)
  expect_equal(AFTERMATH$shot(c(4, 10, 15, 21.5, 30)), flat, tolerance = 1e-4)
  expect_gt(AFTERMATH$shot(12, 0.07), AFTERMATH$shot(12, 0.03))
})

test_that("space only enters the value when the model was fitted with it", {
  d <- fake_shots()
  d$nearest_defender <- runif(nrow(d), 0.5, 12)
  m0 <- fit_shot_value(d)
  m1 <- fit_shot_value(d, space = TRUE)
  expect_equal(shot_value(m0, 12, 0.6, 0, space = 1), shot_value(m0, 12, 0.6, 0, space = 9))
  expect_true("space" %in% names(coef(m1)))
})
