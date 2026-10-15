## Export what the R pipeline computes, so the Python port can be checked
## against it: the shot table with its option lists flattened to long tables,
## the model coefficients, and per-shot scores under a handful of fixed
## specifications. Run from the repository root:
##
##   Rscript python/tests/export_r_reference.R
##
## Everything lands in cache/r-reference/, which is not committed, apart from
## the team corner ratings. run_multiverse.py needs those as well as the tests,
## and Python cannot read an .rds, so they go to cache/corner_ratings.csv.

source("R/geometry.R")
source("R/statsbomb.R")
source("R/features.R")
source("R/value.R")
source("R/multiverse.R")

out <- file.path("cache", "r-reference")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

## Doubles at 17 significant digits, which round-trips exactly. write.csv's
## default of 15 would put the agreement test's floor at the export, not the port.
write_ref <- function(d, name, dir = out) {
  for (n in names(d)) {
    if (is.double(d[[n]])) d[[n]] <- ifelse(is.na(d[[n]]), NA, sprintf("%.17g", d[[n]]))
  }
  write.csv(d, file.path(dir, name), row.names = FALSE, fileEncoding = "UTF-8")
}

flatten <- function(shots, col) {
  do.call(rbind, lapply(seq_len(nrow(shots)), function(i) {
    o <- shots[[col]][[i]]
    if (nrow(o) == 0) return(NULL)
    cbind(shot_id = shots$shot_id[i], option = seq_len(nrow(o)), o)
  }))
}

shots_all <- if (file.exists("cache/shots.rds")) {
  readRDS("cache/shots.rds")
} else {
  build_shots(vapply(sb_matches(), function(m) m$match_id, numeric(1)))
}
shots <- shots_all[shots_all$shot_type != "Free Kick", ]

## Each shot's corner value, joined as analysis/05 joins it
cr <- readRDS("cache/corner_ratings.rds")
write_ref(cr[, c("match_id", "team", "opponent", "matchup")], "corner_ratings.csv", dir = "cache")
shots$corner_value <- cr$matchup[match(paste(shots$match_id, shots$team), paste(cr$match_id, cr$team))]
shots$corner_value[is.na(shots$corner_value)] <- CORNER_XG

write_ref(shots_all[, setdiff(names(shots_all), c("options", "behind"))], "shots.csv")
write_ref(flatten(shots_all, "options"), "options.csv")
write_ref(flatten(shots_all, "behind"), "behind.csv")
write_ref(shots[, c("shot_id", "corner_value")], "corner_values.csv")

models <- list(
  v1_context       = fit_shot_value(shots_all, context = TRUE),
  v1_no_context    = fit_shot_value(shots_all, context = FALSE),
  v1_no_free_kicks = fit_shot_value(shots, context = TRUE),
  v2_context       = fit_shot_value(shots, context = TRUE, keeper = TRUE),
  v2_no_context    = fit_shot_value(shots, context = FALSE, keeper = TRUE),
  v2_space_context    = fit_shot_value(shots, context = TRUE, keeper = TRUE, space = TRUE),
  v2_space_no_context = fit_shot_value(shots, context = FALSE, keeper = TRUE, space = TRUE)
)
write_ref(do.call(rbind, lapply(names(models), function(m) {
  fit <- models[[m]]
  data.frame(model = m, term = names(coef(fit)), estimate = unname(coef(fit)),
             std_error = unname(sqrt(diag(vcov(fit)))), deviance = deviance(fit),
             aic = AIC(fit), iterations = fit$iter)
})), "coefficients.csv")

## Between them these cover every pool, every completion model, both receiver
## contexts, every shot model, the offside rule and aftermath on and off, and
## both views of a corner.
specs <- list(
  v1_ahead_pressure_360 = function()
    score_shots(shots_all, models$v1_context, pool_ahead, completion_pressure, use_context = TRUE),
  v1_clearly_ahead_certain_360 = function()
    score_shots(shots_all, models$v1_context, pool_clearly_ahead, completion_certain, use_context = TRUE),
  v1_in_box_distance_distance_only = function()
    score_shots(shots_all, models$v1_no_context, pool_in_box, completion_distance, use_context = FALSE),
  v2_with_cutbacks_tracking_360 = function()
    score_shots(shots, models$v2_context, pool_with_cutbacks, completion_tracking, use_context = TRUE,
                offside_rule = TRUE, aftermath = AFTERMATH),
  v2_ahead_distance_distance_only = function()
    score_shots(shots, models$v2_no_context, pool_ahead, completion_distance, use_context = FALSE,
                offside_rule = TRUE, aftermath = AFTERMATH),
  v2_space_with_cutbacks_tracking_360_flat = function()
    score_shots(shots, models$v2_space_context, pool_with_cutbacks, completion_tracking,
                use_context = TRUE, offside_rule = TRUE, aftermath = AFTERMATH),
  v2_space_with_cutbacks_tracking_360_by_team = function()
    score_shots(shots, models$v2_space_context, pool_with_cutbacks, completion_tracking,
                use_context = TRUE, offside_rule = TRUE, aftermath = AFTERMATH, team_corners = TRUE),
  v2_space_clearly_ahead_distance_360_by_team = function()
    score_shots(shots, models$v2_space_context, pool_clearly_ahead, completion_distance,
                use_context = TRUE, offside_rule = TRUE, aftermath = AFTERMATH, team_corners = TRUE),
  v2_space_in_box_pressure_distance_only_flat = function()
    score_shots(shots, models$v2_space_no_context, pool_in_box, completion_pressure,
                use_context = FALSE, offside_rule = TRUE, aftermath = AFTERMATH)
)
scored <- lapply(specs, function(f) f())
write_ref(do.call(rbind, lapply(names(scored), function(s) {
  d <- scored[[s]]
  data.frame(spec = s, shot_id = d$shot_id, shot_value = d$shot_value,
             best_alternative = d$best_alternative, edge = d$edge)
})), "scores.csv")

## The bootstrap cannot be matched draw for draw across languages, so only its
## width is exported, from a fixed seed so that this file at least is stable.
set.seed(2023)
boot <- list(
  v1_ahead_pressure_360 = bootstrap_spread(scored$v1_ahead_pressure_360,
                                           function(d) 100 * mean(d$edge > 0), n = 2000),
  v2_space_with_cutbacks_tracking_360_flat = bootstrap_spread(
    scored$v2_space_with_cutbacks_tracking_360_flat, function(d) 100 * mean(d$edge > 0), n = 2000)
)
write_ref(data.frame(spec = names(boot), low = vapply(boot, `[[`, 0, "low"),
                     high = vapply(boot, `[[`, 0, "high"), width = vapply(boot, `[[`, 0, "width"),
                     row.names = NULL), "bootstrap.csv")

cat("written to", out, "\n")
