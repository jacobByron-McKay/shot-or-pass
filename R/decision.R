## The decision score: how often a player shoots when a better pass was on,
## above what the spots they shot from would predict, read against players who
## play the same position.
##
## It runs on the event freeze frames StatsBomb ship with every shot, not the
## 360 frames, so it works on every league and tournament in the open data and
## not just the three with 360. Event frames name the players in them; 360
## frames do not.

#' Read a shot file written by analysis/decision/pull.py.
#'
#' Penalties and direct free kicks are dropped for the same reason as in
#' analysis/05: there is no pass to compare them with.
read_shot_file <- function(path) {
  raw <- jsonlite::stream_in(file(path), verbose = FALSE)
  s <- raw[!(raw$shot_type %in% c("Penalty", "Free Kick")) & !is.na(raw$player_id), ]
  s$goal <- as.integer(s$outcome == "Goal")
  s$xg <- as.numeric(s$xg)
  s$start_year <- as.integer(substr(s$season, 1, 4))
  s$distance <- goal_distance(s$x, s$y)
  s$angle <- goal_angle(s$x, s$y)
  s$header <- s$body_part == "Head"
  s$group <- position_group(s$position)
  rownames(s) <- NULL
  s
}

#' The position a shot was taken from, in the four groups the score is read in.
#'
#' Wing-backs are defenders. Goalkeepers who shoot are left as Other.
position_group <- function(position) {
  ifelse(grepl("Forward|Striker", position), "Forward",
  ifelse(grepl("Wing", position) & !grepl("Back", position), "Winger",
  ifelse(grepl("Midfield", position), "Midfielder",
  ifelse(grepl("Back|Defender", position), "Defender", "Other"))))
}

#' Players in an event freeze frame, in the shape R/features.R works with.
#'
#' The shooter is never in an event frame, so nobody is the actor.
event_frame_players <- function(ff) {
  if (is.null(ff) || NROW(ff) == 0) return(NULL)
  ff <- as.data.frame(ff)
  data.frame(x = ff$x, y = ff$y, teammate = as.logical(ff$teammate), actor = FALSE,
             keeper = !is.na(ff$position) & ff$position == "Goalkeeper")
}

#' Add each shot's positional context and passing options from its freeze frame.
#'
#' Shots without a frame are dropped. The columns match what
#' R/features.R builds from the 360 frames, so score_shots() takes the result
#' as it is.
with_event_frames <- function(s) {
  n <- nrow(s)
  s$defenders_in_cone <- 0
  s$nearest_defender <- 99
  s$keeper_x <- NA_real_
  options <- behind <- vector("list", n)
  seen <- logical(n)
  for (i in seq_len(n)) {
    p <- event_frame_players(s$freeze_frame[[i]])
    if (is.null(p)) next
    seen[i] <- TRUE
    opp <- p[!p$teammate & !p$keeper, ]
    if (nrow(opp)) {
      s$defenders_in_cone[i] <- sum(in_shooting_cone(opp$x, opp$y, s$x[i], s$y[i]))
      s$nearest_defender[i] <- min(sqrt((opp$x - s$x[i])^2 + (opp$y - s$y[i])^2))
    }
    s$keeper_x[i] <- keeper_of(p)[1]
    options[[i]] <- passing_options(p, s$x[i], s$y[i])
    behind[[i]] <- behind_options(p, s$x[i], s$y[i])
  }
  s$options <- I(options)
  s$behind <- I(behind)
  s$freeze_frame <- NULL
  s$end <- NULL
  out <- s[seen, ]
  rownames(out) <- NULL
  out
}

#' Score every shot on the locked model and mark the ones where a pass was better.
#'
#' The settled fixes from analysis/05 are all on: the keeper, space with
#' defenders closing in, offside, cutbacks and lay-offs within 15 yards, the
#' completion model measured on tracking, and what a miss or a failed pass
#' still leads to. Corners take the flat value.
score_decisions <- function(s, model = NULL) {
  if (is.null(model)) model <- fit_shot_value(s, context = TRUE, keeper = TRUE, space = TRUE)
  sc <- score_shots(s, model, pool_with_cutbacks, completion_tracking,
                    offside_rule = TRUE, aftermath = AFTERMATH)
  sc$should_pass <- as.integer(sc$edge < 0)
  sc
}

#' How often a pass is better from where a shot was taken, ignoring who took it.
#'
#' Distance and angle as smooth curves, plus whether it was a header. `strata`
#' adds a column such as the league, for data sets where the freeze frames are
#' not equally full everywhere.
fit_location <- function(scored, strata = NULL) {
  f <- should_pass ~ splines::ns(distance, 4) + splines::ns(angle, 3) + header
  if (!is.null(strata)) f <- stats::update(f, stats::as.formula(paste(". ~ . +", strata)))
  stats::glm(f, family = stats::binomial, data = scored)
}

#' Each shot's decision: should-have-passed, less what its location predicts.
#'
#' Below zero means the player shot when a pass was better less often than a
#' typical player shooting from the same spot. A location model fitted on other
#' shots can be passed in, which is how the backtest keeps the later seasons
#' out of everything it learns from.
decision_score <- function(scored, location = fit_location(scored)) {
  scored$expected <- as.numeric(stats::predict(location, scored, type = "response"))
  scored$decision <- scored$should_pass - scored$expected
  scored
}

#' One row per player: shots, the should-pass share, what was expected, the score.
#'
#' Shares and the score are in percentage points. `vs_position` is the score
#' less the average for players in the same group, and the rank is within the
#' group, best decider first.
player_scores <- function(d, min_shots = 30, by = "player_id") {
  key <- d[[by]]
  rows <- lapply(split(seq_len(nrow(d)), key), function(i) {
    q <- d[i, ]
    data.frame(key = q[[by]][1], player = q$player[1],
               team = names(sort(table(q$team), decreasing = TRUE))[1],
               group = names(sort(table(q$group), decreasing = TRUE))[1],
               shots = nrow(q), goals = sum(q$goal), xg = sum(q$xg),
               should_pass_share = 100 * mean(q$should_pass),
               expected_share = 100 * mean(q$expected),
               decision = 100 * mean(q$decision), stringsAsFactors = FALSE)
  })
  p <- do.call(rbind, rows)
  names(p)[1] <- by
  p <- p[p$shots >= min_shots, ]
  p$vs_position <- p$decision - stats::ave(p$decision, p$group)
  p$rank_in_group <- stats::ave(p$decision, p$group, FUN = function(x) rank(x, ties.method = "min"))
  p$n_in_group <- stats::ave(p$decision, p$group, FUN = length)
  rownames(p) <- NULL
  p[order(p$group, p$rank_in_group), ]
}

#' Split each player's shots in half at random and correlate the two halves.
#'
#' Averaged over `reps` random splits. `group`, when given, takes each group's
#' average out of both halves first, so the answer is how well the score
#' separates players within a position rather than across positions.
split_half <- function(value, player, min_shots = 40, reps = 200, group = NULL) {
  keep <- player %in% names(which(table(player) >= min_shots))
  g <- split(value[keep], player[keep])
  pg <- if (is.null(group)) NULL else {
    first <- tapply(group[keep], player[keep], function(x) names(sort(table(x), decreasing = TRUE))[1])
    first[names(g)]
  }
  r <- replicate(reps, {
    h <- t(vapply(g, function(v) {
      k <- sample(length(v))
      a <- k[c(TRUE, FALSE)]
      c(mean(v[a]), mean(v[-a]))
    }, numeric(2)))
    if (!is.null(pg)) h <- h - apply(h, 2, function(col) stats::ave(col, pg))
    stats::cor(h[, 1], h[, 2])
  })
  list(players = length(g), r = mean(r), shots_per_half = mean(lengths(g)) / 2)
}

#' Shots a player needs before the score reaches a given reliability.
#'
#' Spearman-Brown, from a reliability `r` measured on halves of `shots_per_half`.
shots_to_trust <- function(r, shots_per_half, target = 0.7) {
  if (r <= 0) return(Inf)
  shots_per_half * target * (1 - r) / (r * (1 - target))
}

#' Does one season's score predict the next?
#'
#' A player's average in each season against their average the season after,
#' counting only seasons with `min_shots` or more. Seasons are keyed by the
#' year they start, so a summer tournament sits with the club season it
#' precedes.
season_to_season <- function(value, player, year, min_shots = 20) {
  a <- stats::aggregate(value, list(player = player, year = year),
                        function(v) c(mean(v), length(v)))
  a <- data.frame(player = a$player, year = a$year, m = a$x[, 1], n = a$x[, 2])
  a <- a[a$n >= min_shots, ]
  pr <- merge(a, transform(a, year = year - 1), by = c("player", "year"))
  list(pairs = nrow(pr), r = if (nrow(pr) > 5) stats::cor(pr$m.x, pr$m.y) else NA_real_)
}
