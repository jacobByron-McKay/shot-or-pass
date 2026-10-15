## Wall-clock time for each part of the R pipeline, split the same way
## run_multiverse.py splits the Python one. The analysis scripts time as a
## whole; this separates the build, the two multiverses and the bootstraps.
## Run from the repository root:
##
##   Rscript python/timing.R

source("R/geometry.R")
source("R/statsbomb.R")
source("R/features.R")
source("R/value.R")
source("R/multiverse.R")

timings <- list()
timed <- function(label, expr) {
  t0 <- proc.time()[["elapsed"]]
  out <- expr
  timings[[label]] <<- proc.time()[["elapsed"]] - t0
  out
}
shoot_was_right <- function(d) 100 * mean(d$edge > 0)

ids <- vapply(sb_matches(), function(m) m$match_id, numeric(1))
shots_all <- timed("build", build_shots(ids, verbose = FALSE))

## analysis/02-multiverse.R
with_context <- fit_shot_value(shots_all, context = TRUE)
no_context   <- fit_shot_value(shots_all, context = FALSE)
choices <- list(
  option_pool = OPTION_POOLS,
  completion  = COMPLETION_MODELS,
  receiver_context = list(`360` = TRUE, `distance only` = FALSE),
  margin = list(`any edge` = 0, `clear edge` = 0.02)
)
mv <- timed("the 36", multiverse(choices, function(pick) {
  model <- if (pick$receiver_context) with_context else no_context
  scored <- score_shots(shots_all, model, pick$option_pool, pick$completion,
                        use_context = pick$receiver_context)
  c(shoot_was_right = 100 * mean(scored$edge > pick$margin),
    mean_edge = mean(scored$edge),
    mean_best_alternative = mean(scored$best_alternative))
}, verbose = FALSE))
mid <- score_shots(shots_all, with_context, OPTION_POOLS$ahead,
                   COMPLETION_MODELS$pressure, use_context = TRUE)
boot <- timed("bootstrap, original", bootstrap_spread(mid, shoot_was_right, n = 2000))

## analysis/05-fixes.R
central <- function(shots, model, pool = pool_ahead, completion = completion_pressure,
                    offside_rule = FALSE, aftermath = NULL, team_corners = FALSE) {
  shoot_was_right(score_shots(shots, model, pool, completion, use_context = TRUE,
                              offside_rule = offside_rule, aftermath = aftermath,
                              team_corners = team_corners))
}
shots <- shots_all[shots_all$shot_type != "Free Kick", ]
cr <- readRDS("cache/corner_ratings.rds")
shots$corner_value <- cr$matchup[match(paste(shots$match_id, shots$team), paste(cr$match_id, cr$team))]
shots$corner_value[is.na(shots$corner_value)] <- CORNER_XG
m_v1 <- fit_shot_value(shots_all, context = TRUE)
m_v1_nofk <- fit_shot_value(shots, context = TRUE)
m_keep <- fit_shot_value(shots, context = TRUE, keeper = TRUE)
m_space <- fit_shot_value(shots, context = TRUE, keeper = TRUE, space = TRUE)
steps <- timed("waterfall", c(
  central(shots_all, m_v1),
  central(shots, m_v1_nofk),
  central(shots, m_v1_nofk, offside_rule = TRUE),
  central(shots, m_keep, offside_rule = TRUE),
  central(shots, m_keep, offside_rule = TRUE, aftermath = AFTERMATH),
  central(shots, m_keep, completion = completion_tracking, offside_rule = TRUE,
          aftermath = AFTERMATH),
  central(shots, m_keep, pool = pool_with_cutbacks, completion = completion_tracking,
          offside_rule = TRUE, aftermath = AFTERMATH),
  central(shots, m_space, pool = pool_with_cutbacks, completion = completion_tracking,
          offside_rule = TRUE, aftermath = AFTERMATH),
  central(shots, m_space, pool = pool_with_cutbacks, completion = completion_tracking,
          offside_rule = TRUE, aftermath = AFTERMATH, team_corners = TRUE)
))
m_noctx <- fit_shot_value(shots, context = FALSE, keeper = TRUE, space = TRUE)
choices <- list(
  option_pool = c(OPTION_POOLS, list(with_cutbacks = pool_with_cutbacks)),
  completion  = list(distance = completion_distance, pressure = completion_pressure,
                     tracking = completion_tracking),
  receiver_context = list(`360` = TRUE, `distance only` = FALSE),
  margin = list(`any edge` = 0, `clear edge` = 0.02),
  corners = list(flat = FALSE, `by team` = TRUE)
)
mv2 <- timed("the 96", multiverse(choices, function(pick) {
  model <- if (pick$receiver_context) m_space else m_noctx
  sc <- score_shots(shots, model, pick$option_pool, pick$completion,
                    use_context = pick$receiver_context,
                    offside_rule = TRUE, aftermath = AFTERMATH, team_corners = pick$corners)
  c(shoot_was_right = 100 * mean(sc$edge > pick$margin), mean_edge = mean(sc$edge))
}, verbose = FALSE))
mid <- score_shots(shots, m_space, pool_with_cutbacks, completion_tracking, use_context = TRUE,
                   offside_rule = TRUE, aftermath = AFTERMATH)
boot2 <- timed("bootstrap, after the fixes", bootstrap_spread(mid, shoot_was_right, n = 2000))

## A timing run that quietly got a different answer would be worth nothing.
stopifnot(isTRUE(all.equal(mv$shoot_was_right,
                           read.csv("reports/specification-curve.csv")$shoot_was_right)),
          isTRUE(all.equal(mv2$shoot_was_right,
                           read.csv("reports/specification-curve-v2.csv")$shoot_was_right)))

cat("wall-clock time\n")
for (k in names(timings)) cat(sprintf("  %-30s%6.1f s\n", k, timings[[k]]))
