## What the error analysis changed, one fix at a time, then the multiverse again.
##
## Each fix was found by checking the model against something it had not seen:
## the passes players actually made, tracking data, and the footage. The ones
## that settle a question go in for good. The ones where reasonable people
## could still disagree stay as branches of the multiverse.

source("R/geometry.R")
source("R/features.R")
source("R/value.R")
source("R/multiverse.R")

shots_all <- readRDS("cache/shots.rds")
central <- function(shots, model, pool = pool_ahead, completion = completion_pressure,
                    offside_rule = FALSE, aftermath = NULL, team_corners = FALSE) {
  sc <- score_shots(shots, model, pool, completion, use_context = TRUE,
                    offside_rule = offside_rule, aftermath = aftermath, team_corners = team_corners)
  100 * mean(sc$edge > 0)
}

## The fixes, applied cumulatively to one middle specification: every option
## ahead, the pressure completion model, defender context, any edge.
shots <- shots_all[shots_all$shot_type != "Free Kick", ]

## each shot's corner value: this team's corners against this opponent's, from
## earlier games weighted by how many of today's starters played in them
cr <- readRDS("cache/corner_ratings.rds")
shots$corner_value <- cr$matchup[match(paste(shots$match_id, shots$team), paste(cr$match_id, cr$team))]
cat("shots with a team corner rating:", sprintf("%.1f%%", 100 * mean(!is.na(shots$corner_value))), "
")
shots$corner_value[is.na(shots$corner_value)] <- CORNER_XG

m_v1 <- fit_shot_value(shots_all, context = TRUE)
m_v1_nofk <- fit_shot_value(shots, context = TRUE)
m_keep <- fit_shot_value(shots, context = TRUE, keeper = TRUE)
m_space <- fit_shot_value(shots, context = TRUE, keeper = TRUE, space = TRUE)

steps <- list(
  c("as submitted", central(shots_all, m_v1)),
  c("drop direct free kicks", central(shots, m_v1_nofk)),
  c("+ offside options removed", central(shots, m_v1_nofk, offside_rule = TRUE)),
  c("+ keeper off the line", central(shots, m_keep, offside_rule = TRUE)),
  c("+ what a miss or a bad pass still leads to", central(shots, m_keep, offside_rule = TRUE,
                                                     aftermath = AFTERMATH)),
  c("+ completion measured on tracking (lanes)", central(shots, m_keep, completion = completion_tracking,
                                                     offside_rule = TRUE, aftermath = AFTERMATH)),
  c("+ cutbacks and lay-offs", central(shots, m_keep, pool = pool_with_cutbacks,
                                       completion = completion_tracking,
                                       offside_rule = TRUE, aftermath = AFTERMATH)),
  c("+ space, with defenders closing in", central(shots, m_space, pool = pool_with_cutbacks,
                                                  completion = completion_tracking,
                                                  offside_rule = TRUE, aftermath = AFTERMATH)),
  c("(branch) team corner ratings", central(shots, m_space, pool = pool_with_cutbacks,
                                            completion = completion_tracking, offside_rule = TRUE,
                                            aftermath = AFTERMATH, team_corners = TRUE))
)
wf <- data.frame(step = vapply(steps, `[`, "", 1),
                 shoot_was_right = round(as.numeric(vapply(steps, `[`, "", 2)), 1))
wf$change <- c(NA, round(diff(wf$shoot_was_right), 1))
cat("\none specification, fix by fix: share of shots where shooting was right\n")
print(wf, row.names = FALSE)

## The multiverse after the fixes. Offside, the keeper, the aftermath and space
## with defenders closing in are settled by the rules or the data, so they are
## always on. Assuming every pass arrives is no longer defensible (68% do), so
## that branch goes. Cutbacks join the option pool, the measured completion
## model joins the assumed ones, and a team's own corner record is tested
## against the flat average.
m_ctx   <- m_space
m_noctx <- fit_shot_value(shots, context = FALSE, keeper = TRUE, space = TRUE)
choices <- list(
  option_pool = c(OPTION_POOLS, list(with_cutbacks = pool_with_cutbacks)),
  completion  = list(distance = completion_distance, pressure = completion_pressure,
                     tracking = completion_tracking),
  receiver_context = list(`360` = TRUE, `distance only` = FALSE),
  margin = list(`any edge` = 0, `clear edge` = 0.02),
  corners = list(flat = FALSE, `by team` = TRUE)
)
cat("\nrunning", nrow(specifications(choices)), "specifications\n")
t0 <- Sys.time()
mv <- multiverse(choices, function(pick) {
  model <- if (pick$receiver_context) m_ctx else m_noctx
  sc <- score_shots(shots, model, pick$option_pool, pick$completion,
                    use_context = pick$receiver_context,
                    offside_rule = TRUE, aftermath = AFTERMATH, team_corners = pick$corners)
  c(shoot_was_right = 100 * mean(sc$edge > pick$margin), mean_edge = mean(sc$edge))
})
cat("multiverse run time:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")

cat("\nshare of shots where shooting beat the best alternative, after the fixes\n")
cat("  lowest specification: ", sprintf("%.1f%%", min(mv$shoot_was_right)), "\n")
cat("  highest specification:", sprintf("%.1f%%", max(mv$shoot_was_right)), "\n")
cat("  spread:               ", sprintf("%.1f points", diff(range(mv$shoot_was_right))), "\n")
sens <- sensitivity(mv, "shoot_was_right", decisions = names(choices))
print(data.frame(decision = sens$decision, levels = sens$levels, low = round(sens$low, 1),
                 high = round(sens$high, 1), spread = round(sens$spread, 1)), row.names = FALSE)

mid <- score_shots(shots, m_ctx, pool_with_cutbacks, completion_tracking, use_context = TRUE,
                   offside_rule = TRUE, aftermath = AFTERMATH)
## The same fixed seed as analysis/02, 2023 for the tournament year, so the
## interval and the ratio print the same on every run.
set.seed(2023)
boot <- bootstrap_spread(mid, function(d) 100 * mean(d$edge > 0), n = 2000)
cat("\nsampling: 95% interval on the fixed central specification",
    sprintf("[%.1f%%, %.1f%%], width %.1f points", boot$low, boot$high, boot$width), "\n")
cat("ratio definitional to sampling:", round(diff(range(mv$shoot_was_right)) / boot$width, 2), "\n")

dir.create("reports", showWarnings = FALSE)
write.csv(wf, "reports/fix-waterfall.csv", row.names = FALSE)
write.csv(mv, "reports/specification-curve-v2.csv", row.names = FALSE)
saveRDS(list(waterfall = wf, mv = mv, sens = sens, boot = boot), "cache/results_v2.rds")
cat("written to reports/fix-waterfall.csv and reports/specification-curve-v2.csv\n")
