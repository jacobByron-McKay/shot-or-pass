## The 96 from analysis/05 again, run through the multiverse package.
##
## 05 and 06 run their multiverses on the small harness in R/multiverse.R: the
## choices go in a list, and one function takes a pick from each and scores
## every shot. The multiverse package on CRAN (Sarma et al., CHI 2023) turns
## that inside out. The analysis is written once, top to bottom, and each
## choice is a branch() on the line where it is made. The package works out
## the paths, runs them, and keeps each one's code and results. The end of the
## script checks every figure against what 05 wrote, so run it after 05.

source("R/geometry.R")
source("R/features.R")
source("R/value.R")
source("R/multiverse.R")
suppressPackageStartupMessages(library(multiverse))

#' Every option for every shot in one table, a row per possible receiver.
#'
#' Copied unchanged from analysis/06-multiverse-fast.R, which runs its whole
#' pipeline when sourced. `behind` marks the lay-offs and cutbacks, `space` is
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
#' Also copied unchanged from analysis/06. A model fitted without a term
#' simply never reads its column.
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

elapsed <- function(t0) proc.time()[["elapsed"]] - t0

## the same shots as 05, with each shot's corner value joined the same way
shots_all <- readRDS("cache/shots.rds")
shots <- shots_all[shots_all$shot_type != "Free Kick", ]
cr <- readRDS("cache/corner_ratings.rds")
shots$corner_value <- cr$matchup[match(paste(shots$match_id, shots$team), paste(cr$match_id, cr$team))]
shots$corner_value[is.na(shots$corner_value)] <- CORNER_XG

t0 <- proc.time()[["elapsed"]]
opts <- long_options(shots)

## R/multiverse.R has a multiverse() of its own, the harness this replaces,
## and the global one is found first. Hence the ::.
M <- multiverse::multiverse()

## Each inside() is one level of the package's tree. Whatever a block computes
## is computed once per combination of the choices above it and shared by
## every universe below, so the blocks run in pipeline order and the cheapest
## choice goes last. Two habits keep it honest. inside() runs the first
## universe every time it is called unless told not to, and those runs leave
## values behind that a later block can pick up, so that is switched off. And
## no block reassigns a name an earlier block made: with the default runs on,
## `x <- x + 1` in a later block can be applied twice without any error.

## whether the shot model gets to see the bodies in the shooting cone. The
## choice lives where the model is fitted, so it is fitted twice, not 96 times.
## The shooter is valued on the space they had.
inside(M, {
  use_context <- branch(receiver_context, "360" ~ TRUE, "distance only" ~ FALSE)
  model <- fit_shot_value(shots, context = use_context, keeper = TRUE, space = TRUE)
  sv <- model_value(model, shots, use_context, shots$nearest_defender)
}, .execute_default = FALSE)

## who counts as an alternative. The first three pools only look at teammates
## ahead of the ball; with cutbacks, the lay-offs behind it come in too.
## Offside is settled by the rules, so it is always applied. Receivers are
## valued on the space they will have once defenders close in.
inside(M, {
  pool <- branch(option_pool,
                 "ahead"         ~ pool_ahead(opts[!opts$behind, ]),
                 "clearly_ahead" ~ pool_clearly_ahead(opts[!opts$behind, ]),
                 "in_box"        ~ pool_in_box(opts[!opts$behind, ]),
                 "with_cutbacks" ~ opts)
  o <- pool[!pool$offside, ]
  receive <- model_value(model, o, use_context, o$space)
}, .execute_default = FALSE)

## how likely the pass is to arrive: two assumed models, one measured on tracking
inside(M, {
  arrive <- branch(completion,
                   "distance" ~ completion_distance(o$pass_length, o$nearest_defender),
                   "pressure" ~ completion_pressure(o$pass_length, o$nearest_defender),
                   "tracking" ~ completion_tracking(o$pass_length, o$nearest_defender, o$lane_blockers))
}, .execute_default = FALSE)

## what a corner won from a miss is worth, the flat average or this team's own
## record against this opponent. It feeds both sides of the comparison, so the
## scoring finishes here. A shot with nobody left in the pool keeps a best
## alternative of zero.
inside(M, {
  corner_value <- branch(corners,
                         "flat"    ~ rep(CORNER_XG, nrow(shots)),
                         "by team" ~ shots$corner_value)
  receive_then <- receive + (1 - receive) * AFTERMATH$shot(o$distance, corner_value[o$shot])
  value <- arrive * receive_then + (1 - arrive) * AFTERMATH$failed_pass
  best <- numeric(nrow(shots))
  top <- tapply(value, o$shot, max)
  best[as.integer(names(top))] <- top
  shot_value <- sv + (1 - sv) * AFTERMATH$shot(shots$distance, corner_value)
  edge <- shot_value - best
}, .execute_default = FALSE)

## the margin only changes how an edge is read, so the 96 share 48 scorings
inside(M, {
  shoot_was_right <- 100 * mean(edge > branch(margin, "any edge" ~ 0, "clear edge" ~ 0.02))
  mean_edge <- mean(edge)
}, .execute_default = FALSE)

execute_multiverse(M)

## a universe that fails only raises a warning, and its results come back as
## NA, so a failure has to be looked for
universes <- expand(M)
failed <- vapply(universes$.errors, function(e) any(!is.na(e)), logical(1))
if (any(failed)) stop(sum(failed), " universes failed, see expand(M)$.errors")

decisions <- names(parameters(M))
res <- extract_variables(universes, shoot_was_right, mean_edge)
mv <- as.data.frame(res[c(".universe", decisions, "shoot_was_right", "mean_edge")])
secs <- elapsed(t0)

cat("share of shots where shooting beat the best alternative, the package's way\n")
cat(sprintf("  %d universes: %.1f%% to %.1f%%, spread %.1f points, %.2f s\n", nrow(mv),
            min(mv$shoot_was_right), max(mv$shoot_was_right),
            diff(range(mv$shoot_was_right)), secs))
cat("  (including the long table and the two model fits)\n")
sens <- sensitivity(mv, "shoot_was_right", decisions = decisions)
print(data.frame(decision = sens$decision, levels = sens$levels, low = round(sens$low, 1),
                 high = round(sens$high, 1), spread = round(sens$spread, 1)), row.names = FALSE)

## The package numbers its universes in its own order, so the check against
## 05 joins on the five choices rather than trusting row positions.
slow <- read.csv("reports/specification-curve-v2.csv")
both <- merge(slow, mv, by = decisions, suffixes = c("_05", "_package"))
if (nrow(mv) != 96 || nrow(both) != 96) {
  stop("the package and 05 do not hold the same 96 specifications")
}
gap <- c(shoot_was_right = max(abs(both$shoot_was_right_05 - both$shoot_was_right_package)),
         mean_edge = max(abs(both$mean_edge_05 - both$mean_edge_package)))
if (any(gap > 1e-9)) stop("results differ from 05 by up to ", signif(max(gap), 3))
cat("\nlargest difference from the 96 that 05 wrote: shoot_was_right",
    signif(gap[["shoot_was_right"]], 2), ", mean_edge", signif(gap[["mean_edge"]], 2), "\n")

## Every universe keeps the code it ran with its branches filled in, which is
## the thing the harness cannot give you. The most pessimistic one is written
## out as a script that runs on its own after the setup above.
low <- which.min(mv$shoot_was_right)
dir.create("scratch", showWarnings = FALSE)
writeLines(c(sprintf("## universe %d: %s, shooting right %.1f%%", mv$.universe[low],
                     paste(unlist(mv[low, decisions]), collapse = ", "), mv$shoot_was_right[low]),
             unlist(lapply(universes$.code[[low]], deparse))),
           "scratch/multiverse_pkg_lowest_universe.R")
write.csv(mv[c(".universe", "option_pool", "completion", "receiver_context", "margin", "corners",
               "shoot_was_right", "mean_edge")],
          "scratch/multiverse_pkg_results.csv", row.names = FALSE)
cat("written to scratch/multiverse_pkg_results.csv and scratch/multiverse_pkg_lowest_universe.R\n")
