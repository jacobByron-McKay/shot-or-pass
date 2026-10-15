## The multiverses from 02 and 05 again, written the way R wants them written.
##
## score_shots() walks the shots one at a time and asks predict() what each
## shot's receivers are worth, which comes to about 140,000 calls over the 36
## and the 96. Here every option for every shot sits in one long table, a
## specification is a few vectorised lines over it, and the best option for
## each shot is a grouped maximum. Same answers, and the end of the script
## checks that they are, so run it after 02 and 05.

source("R/geometry.R")
source("R/features.R")
source("R/value.R")
source("R/multiverse.R")

#' Every option for every shot in one table, a row per possible receiver.
#'
#' `shot` is the row of the shot table the option belongs to. `behind` marks
#' the lay-offs and cutbacks, which only the cutback pool lets in. `space` is
#' the room the receiver will have left by the time they shoot.
long_options <- function(shots) {
  stack <- function(col, behind) {
    d <- do.call(rbind, shots[[col]])
    d$shot <- rep(seq_len(nrow(shots)), vapply(shots[[col]], nrow, integer(1)))
    d$behind <- rep(behind, nrow(d))
    d
  }
  opts <- rbind(stack("options", FALSE), stack("behind", TRUE))
  opts$keeper_x <- shots$keeper_x[opts$shot]
  opts$space <- closing_in(opts$nearest_defender, opts$pass_length)
  opts
}

#' What the fitted model says each row is worth, straight from its coefficients.
#'
#' The design matrix predict() builds from the formula, built once for the
#' whole table instead of once per shot. A model fitted without a term simply
#' never reads its column.
model_value <- function(model, d, use_context = TRUE, space = SPACE_CAP) {
  unseen <- is.na(d$keeper_x)
  X <- cbind(`(Intercept)` = 1, distance = d$distance, angle = d$angle,
             defenders_in_cone = if (use_context) d$defenders_in_cone else 0,
             keeper_off_line = ifelse(unseen, KEEPER_OFF_LINE_TYPICAL, GOAL_X - d$keeper_x),
             keeper_missing = as.numeric(unseen),
             space = pmin(space, SPACE_CAP))
  b <- stats::coef(model)
  model$family$linkinv(drop(X[, names(b), drop = FALSE] %*% b))
}

## The option pools from R/value.R as filters on the long table. The first
## three only look at teammates ahead of the ball; with cutbacks, everyone.
LONG_POOLS <- list(
  ahead         = function(o) pool_ahead(o[!o$behind, ]),
  clearly_ahead = function(o) pool_clearly_ahead(o[!o$behind, ]),
  in_box        = function(o) pool_in_box(o[!o$behind, ]),
  with_cutbacks = function(o) o
)

#' Score every shot under one specification, all shots at once.
#'
#' The arithmetic of score_shots() and best_alternative(), unchanged. A shot
#' with nobody left in the pool keeps a best alternative of zero. Receivers are
#' valued on the space they will have once defenders close in, the shooter on
#' the space they had.
score_long <- function(shots, opts, model, pool, completion, use_context = TRUE,
                       offside_rule = FALSE, aftermath = NULL, team_corners = FALSE) {
  cv <- if (team_corners) shots$corner_value else rep(CORNER_XG, nrow(shots))
  o <- pool(opts)
  if (offside_rule) o <- o[!o$offside, ]
  receive <- model_value(model, o, use_context, o$space)
  arrive <- completion(o$pass_length, o$nearest_defender, o$lane_blockers)
  value <- if (is.null(aftermath)) receive * arrive else {
    receive <- receive + (1 - receive) * aftermath$shot(o$distance, cv[o$shot])
    arrive * receive + (1 - arrive) * aftermath$failed_pass
  }
  best <- numeric(nrow(shots))
  top <- tapply(value, o$shot, max)
  best[as.integer(names(top))] <- top

  sv <- model_value(model, shots, use_context, shots$nearest_defender)
  if (!is.null(aftermath)) sv <- sv + (1 - sv) * aftermath$shot(shots$distance, cv)
  shots$shot_value <- sv
  shots$best_alternative <- best
  shots$edge <- sv - best
  shots
}

elapsed <- function(t0) proc.time()[["elapsed"]] - t0

## The original 36, as in analysis/02.
shots_all <- readRDS("cache/shots.rds")
with_context <- fit_shot_value(shots_all, context = TRUE)
no_context   <- fit_shot_value(shots_all, context = FALSE)
choices36 <- list(
  option_pool = LONG_POOLS[names(OPTION_POOLS)],
  completion  = COMPLETION_MODELS,
  receiver_context = list(`360` = TRUE, `distance only` = FALSE),
  margin = list(`any edge` = 0, `clear edge` = 0.02)
)

t0 <- proc.time()[["elapsed"]]
opts_all <- long_options(shots_all)
mv36 <- multiverse(choices36, function(pick) {
  model <- if (pick$receiver_context) with_context else no_context
  sc <- score_long(shots_all, opts_all, model, pick$option_pool, pick$completion,
                   use_context = pick$receiver_context)
  c(shoot_was_right = 100 * mean(sc$edge > pick$margin),
    mean_edge = mean(sc$edge),
    mean_best_alternative = mean(sc$best_alternative))
}, verbose = FALSE)
secs36 <- elapsed(t0)

## The 96 after the fixes, as in analysis/05, with each shot's corner value
## joined the same way.
shots <- shots_all[shots_all$shot_type != "Free Kick", ]
cr <- readRDS("cache/corner_ratings.rds")
shots$corner_value <- cr$matchup[match(paste(shots$match_id, shots$team), paste(cr$match_id, cr$team))]
shots$corner_value[is.na(shots$corner_value)] <- CORNER_XG
m_ctx   <- fit_shot_value(shots, context = TRUE, keeper = TRUE, space = TRUE)
m_noctx <- fit_shot_value(shots, context = FALSE, keeper = TRUE, space = TRUE)
choices96 <- list(
  option_pool = LONG_POOLS,
  completion  = list(distance = completion_distance, pressure = completion_pressure,
                     tracking = completion_tracking),
  receiver_context = list(`360` = TRUE, `distance only` = FALSE),
  margin = list(`any edge` = 0, `clear edge` = 0.02),
  corners = list(flat = FALSE, `by team` = TRUE)
)

t0 <- proc.time()[["elapsed"]]
opts <- long_options(shots)
mv96 <- multiverse(choices96, function(pick) {
  model <- if (pick$receiver_context) m_ctx else m_noctx
  sc <- score_long(shots, opts, model, pick$option_pool, pick$completion,
                   use_context = pick$receiver_context,
                   offside_rule = TRUE, aftermath = AFTERMATH, team_corners = pick$corners)
  c(shoot_was_right = 100 * mean(sc$edge > pick$margin), mean_edge = mean(sc$edge))
}, verbose = FALSE)
secs96 <- elapsed(t0)

cat("share of shots where shooting was right, and the time to get there\n")
cat(sprintf("  the original 36:        %.1f%% to %.1f%%, %.2f s\n",
            min(mv36$shoot_was_right), max(mv36$shoot_was_right), secs36))
cat(sprintf("  the 96 after the fixes: %.1f%% to %.1f%%, %.2f s\n",
            min(mv96$shoot_was_right), max(mv96$shoot_was_right), secs96))
cat("  (both include building the long table)\n")

## A faster answer is only worth having if it is the same answer. First every
## figure against what 02 and 05 wrote, then every shot's verdict under every
## specification against score_shots() itself.
same_curve <- function(mv, file) {
  slow <- read.csv(file)
  decisions <- intersect(c("option_pool", "completion", "receiver_context", "margin", "corners"),
                         names(slow))
  for (d in decisions) {
    if (!identical(as.character(mv[[d]]), as.character(slow[[d]]))) {
      stop(file, ": specifications in a different order at ", d)
    }
  }
  gap <- max(abs(as.matrix(mv[setdiff(names(slow), decisions)]) -
                 as.matrix(slow[setdiff(names(slow), decisions)])))
  if (gap > 1e-9) stop(file, ": results differ by up to ", signif(gap, 3))
  gap
}
gaps <- c(same_curve(mv36, "reports/specification-curve.csv"),
          same_curve(mv96, "reports/specification-curve-v2.csv"))
cat("\nlargest difference from the results 02 and 05 wrote:", signif(max(gaps), 2), "\n")

## The margin does not change the scoring, so each combination is scored once
## each way and judged at both margins. This part takes a couple of minutes,
## nearly all of it in score_shots().
SHOT_BY_SHOT <- c(OPTION_POOLS, list(with_cutbacks = pool_with_cutbacks))
verdicts_against_score_shots <- function(shots, opts, choices, ctx_model, noctx_model, ...) {
  pools <- names(choices$option_pool)
  scoring <- list(option_pool = setNames(as.list(pools), pools),
                  completion = choices$completion,
                  receiver_context = choices$receiver_context,
                  corners = choices$corners %||% list(flat = FALSE))
  multiverse(scoring, function(pick) {
    model <- if (pick$receiver_context) ctx_model else noctx_model
    slow <- score_shots(shots, model, SHOT_BY_SHOT[[pick$option_pool]], pick$completion,
                        use_context = pick$receiver_context, team_corners = pick$corners, ...)
    fast <- score_long(shots, opts, model, LONG_POOLS[[pick$option_pool]], pick$completion,
                       use_context = pick$receiver_context, team_corners = pick$corners, ...)
    c(verdicts_differ = sum(vapply(choices$margin, function(m) {
        sum((slow$edge > m) != (fast$edge > m))
      }, numeric(1))),
      edge_gap = max(abs(slow$edge - fast$edge)))
  })
}
cat("\nchecking every shot against score_shots()\n")
check <- rbind(
  verdicts_against_score_shots(shots_all, opts_all, choices36, with_context, no_context),
  verdicts_against_score_shots(shots, opts, choices96, m_ctx, m_noctx,
                               offside_rule = TRUE, aftermath = AFTERMATH)
)
if (any(check$verdicts_differ > 0)) {
  stop("verdicts differ from score_shots() on ", sum(check$verdicts_differ), " shots")
}
cat("every shot gets the same verdict under all", nrow(mv36) + nrow(mv96),
    "specifications; largest gap in any shot's edge:", signif(max(check$edge_gap), 2), "\n")
