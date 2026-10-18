fake_decisions <- function(players = 60, shots = 40, trait_sd = 0.15, groups = NULL) {
  set.seed(19)
  trait <- rnorm(players, 0, trait_sd)
  g <- if (is.null(groups)) rep("Forward", players) else rep_len(groups, players)
  d <- data.frame(player_id = rep(seq_len(players), each = shots),
                  group = rep(g, each = shots),
                  distance = runif(players * shots, 6, 30))
  d$angle <- goal_angle(GOAL_X - d$distance, 40)
  d$header <- runif(nrow(d)) < 0.15
  p <- plogis(-1.5 + 0.08 * d$distance + 4 * trait[d$player_id])
  d$should_pass <- rbinom(nrow(d), 1, p)
  d$start_year <- 2020 + (seq_len(nrow(d)) - 1) %% shots %/% (shots / 2)
  d
}

test_that("positions fall into the four groups the score is read in", {
  pos <- c("Center Forward", "Secondary Striker", "Left Wing", "Right Wing Back",
           "Center Attacking Midfield", "Left Midfield", "Left Center Back", "Goalkeeper")
  expect_equal(position_group(pos), c("Forward", "Forward", "Winger", "Defender",
                                      "Midfielder", "Midfielder", "Defender", "Other"))
})

test_that("an event frame becomes the players table, keeper marked, nobody the actor", {
  ff <- data.frame(x = c(110, 118, 105), y = c(40, 40, 30), teammate = c(TRUE, FALSE, FALSE),
                   player = c("a", "b", "c"), position = c("Center Forward", "Goalkeeper", "Right Back"))
  p <- event_frame_players(ff)
  expect_equal(p$keeper, c(FALSE, TRUE, FALSE))
  expect_false(any(p$actor))
  expect_null(event_frame_players(data.frame()))
  expect_null(event_frame_players(NULL))
})

test_that("shots get options ahead, cutbacks behind, and shots with no frame drop out", {
  ff <- data.frame(x = c(112, 100, 116, 109), y = c(38, 44, 40, 41),
                   teammate = c(TRUE, TRUE, FALSE, FALSE),
                   player = c("ahead", "behind", "keeper", "defender"),
                   position = c("Center Forward", "Center Midfield", "Goalkeeper", "Center Back"))
  s <- data.frame(x = c(105, 100), y = c(40, 40))
  s$freeze_frame <- list(ff, data.frame())
  out <- with_event_frames(s)
  expect_equal(nrow(out), 1)
  expect_equal(nrow(out$options[[1]]), 1)
  expect_equal(nrow(out$behind[[1]]), 1)
  expect_equal(out$keeper_x, 116)
  expect_equal(out$defenders_in_cone, 1)
  expect_equal(out$nearest_defender, sqrt(16 + 1))
})

test_that("the decision score averages to zero on the shots its location model saw", {
  d <- fake_decisions()
  d <- decision_score(d)
  expect_equal(mean(d$decision), 0, tolerance = 1e-8)
})

test_that("shooting from far out is not held against a player", {
  set.seed(4)
  d <- data.frame(player_id = rep(1:2, each = 400), distance = c(runif(400, 25, 30), runif(400, 6, 10)))
  d$angle <- goal_angle(GOAL_X - d$distance, 40)
  d$header <- FALSE
  d$should_pass <- rbinom(nrow(d), 1, plogis(-3 + 0.15 * d$distance))
  d <- decision_score(d)
  raw_gap <- diff(tapply(d$should_pass, d$player_id, mean))
  adj_gap <- diff(tapply(d$decision, d$player_id, mean))
  expect_gt(abs(raw_gap), 0.3)
  expect_lt(abs(adj_gap), 0.05)
})

test_that("a location model fitted elsewhere can score new shots", {
  d <- fake_decisions()
  early <- d[d$start_year == 2020, ]
  late <- d[d$start_year == 2021, ]
  loc <- fit_location(early)
  scored <- decision_score(late, loc)
  expect_equal(nrow(scored), nrow(late))
  expect_true(all(scored$expected > 0 & scored$expected < 1))
})

test_that("split-half finds a real trait and finds nothing in noise", {
  d <- decision_score(fake_decisions(trait_sd = 0.3))
  set.seed(1)
  real <- split_half(d$decision, d$player_id, min_shots = 40, reps = 50)
  d$noise <- rnorm(nrow(d))
  none <- split_half(d$noise, d$player_id, min_shots = 40, reps = 50)
  expect_gt(real$r, 0.5)
  expect_lt(abs(none$r), 0.2)
  expect_equal(real$players, 60)
  expect_equal(real$shots_per_half, 20)
})

test_that("reading within position removes what the position alone explains", {
  set.seed(8)
  d <- data.frame(player_id = rep(1:60, each = 40), group = rep(c("Forward", "Defender"), each = 30 * 40))
  d$value <- ifelse(d$group == "Forward", -0.3, 0.3) + rnorm(nrow(d), 0, 0.3)
  overall <- split_half(d$value, d$player_id, reps = 50)
  within <- split_half(d$value, d$player_id, reps = 50, group = d$group)
  expect_gt(overall$r, 0.8)
  expect_lt(abs(within$r), 0.3)
})

test_that("shots needed follows Spearman-Brown", {
  expect_equal(shots_to_trust(0.7, 20), 20)
  expect_equal(shots_to_trust(0.5, 20), 20 * 0.7 * 0.5 / (0.5 * 0.3))
  expect_gt(shots_to_trust(0.3, 20), shots_to_trust(0.6, 20))
  expect_equal(shots_to_trust(0, 20), Inf)
  expect_equal(shots_to_trust(-0.1, 20), Inf)
})

test_that("season to season pairs a season with the next one only", {
  d <- data.frame(player = rep(1:10, each = 60), year = rep(c(2018, 2019, 2021), each = 20, times = 10))
  set.seed(2)
  d$value <- (d$player / 10) + rnorm(nrow(d), 0, 0.05)
  ss <- season_to_season(d$value, d$player, d$year, min_shots = 20)
  expect_equal(ss$pairs, 10)
  expect_gt(ss$r, 0.9)
  expect_true(is.na(season_to_season(d$value, d$player, d$year, min_shots = 21)$r))
})

test_that("the player table ranks within position and drops thin samples", {
  d <- decision_score(fake_decisions(players = 12, shots = 40, groups = c("Forward", "Midfielder")))
  d <- d[!(d$player_id == 1 & seq_len(nrow(d)) > 20), ]
  d$player <- paste("player", d$player_id)
  d$team <- "a team"
  d$goal <- 0
  d$xg <- 0.1
  p <- player_scores(d, min_shots = 30)
  expect_equal(nrow(p), 11)
  expect_false(1 %in% p$player_id)
  expect_equal(as.numeric(tapply(p$vs_position, p$group, sum)), c(0, 0), tolerance = 1e-8)
  fw <- p[p$group == "Forward", ]
  expect_equal(fw$player_id[fw$rank_in_group == 1], fw$player_id[which.min(fw$decision)])
  expect_equal(unique(fw$n_in_group), nrow(fw))
})
