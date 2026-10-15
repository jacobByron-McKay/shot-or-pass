## What a shot was worth, and what the best thing the player could have done
## instead was worth.

#' Fit a shot value model on the tournament's own shots.
#'
#' Three terms, all readable. Distance and goalmouth angle are the standard
#' pair. Bodies in the shooting cone is the term that only exists because of
#' the freeze frames, and it is the one that earns its place. `keeper = TRUE`
#' adds how far the keeper stands off the goal line, plus a flag for frames
#' where the camera missed the keeper.
#'
#' Why distance off the line and not the share of the goal the keeper leaves
#' open: both were tried on the tournament's shots. Off the line improves the
#' model (AIC down 12.3, p < 0.0001; goals roughly double once the keeper is
#' four yards out). The open-goal geometry does nothing (p = 0.74) and neither
#' does standing sideways out of position (p = 0.41). A keeper who has come a
#' long way out is usually a keeper who has been caught, not one covering the
#' angle better.
fit_shot_value <- function(shots, context = TRUE, keeper = FALSE, space = FALSE) {
  f <- if (context) goal ~ distance + angle + defenders_in_cone
       else         goal ~ distance + angle
  if (keeper) {
    shots <- with_keeper_terms(shots)
    f <- stats::update(f, . ~ . + keeper_off_line + keeper_missing)
  }
  if (space) {
    shots$space <- pmin(shots$nearest_defender, SPACE_CAP)
    f <- stats::update(f, . ~ . + space)
  }
  stats::glm(f, family = stats::binomial, data = shots)
}

## Space: yards to the nearest outfield defender, capped where it stops
## mattering. Worth +0.22 a yard on the tournament's shots (p = 0.0005) and
## +0.18 across 33,000 women's shots, on top of every other term.
SPACE_CAP <- 10

#' The space a receiver will have when they shoot, not when the pass leaves.
#'
#' Two stages, both measured on SkillCorner's A-League tracking. While the ball
#' travels (about 12.3 yards a second) a receiver with room loses some of it:
#' seven to twelve yards becomes about four to eight, and a player already tight
#' stays tight (1,137 completed passes, scratch/sc_closing.py). Then, between the
#' first touch and the shot, defenders keep coming: 325 receptions that became
#' shots went from a median 4.7 yards to 2.5 when a touch was taken
#' (scratch/sc_receive_to_shot.py). The shooter's own space is measured at the
#' shot, so this puts both sides of the comparison at the same moment.
closing_in <- function(space_at_pass, pass_length) {
  t <- pass_length / 12.3
  on_receipt <- 0.652 + 0.647 * space_at_pass + 0.209 * t - 0.044 * space_at_pass * t
  pmin(1.808 + 0.256 * on_receipt, SPACE_CAP)
}

#' Apply a fitted shot model to arbitrary positions.
#'
#' `keeper_x` is where the keeper stood in the frame, the same for the shooter
#' and every teammate in it. NA means the camera did not catch them.
shot_value <- function(model, distance, angle, defenders_in_cone = 0,
                       keeper_x = NA_real_, space = SPACE_CAP) {
  nd <- data.frame(distance = distance, angle = angle,
                   defenders_in_cone = defenders_in_cone)
  if ("space" %in% names(stats::coef(model))) nd$space <- pmin(rep_len(space, nrow(nd)), SPACE_CAP)
  if ("keeper_off_line" %in% names(stats::coef(model))) {
    kx <- rep_len(keeper_x, nrow(nd))
    nd$keeper_missing <- as.numeric(is.na(kx))
    nd$keeper_off_line <- ifelse(is.na(kx), KEEPER_OFF_LINE_TYPICAL, GOAL_X - kx)
  }
  as.numeric(stats::predict(model, nd, type = "response"))
}

## How far off the line the keeper usually is (median across the tournament's
## shots, 2.4 yards). Frames without a keeper get this plus a flag, so the
## model learns what an unseen keeper is worth instead of being told.
KEEPER_OFF_LINE_TYPICAL <- 2.4

with_keeper_terms <- function(shots) {
  shots$keeper_missing <- as.numeric(is.na(shots$keeper_x))
  shots$keeper_off_line <- ifelse(is.na(shots$keeper_x), KEEPER_OFF_LINE_TYPICAL,
                                  GOAL_X - shots$keeper_x)
  shots
}

## Defensible views of how likely a pass is to arrive. The first three are
## assumptions somebody would defend in a meeting, and none of them is written
## down in the analyses that rely on them. The fourth is measured.

completion_certain <- function(pass_length, nearest_defender, ...) {
  rep(1, length(pass_length))
}

completion_distance <- function(pass_length, nearest_defender, ...) {
  stats::plogis(2.6 - 0.06 * pass_length)
}

completion_pressure <- function(pass_length, nearest_defender, ...) {
  stats::plogis(2.2 - 0.055 * pass_length + 0.10 * pmin(nearest_defender, 15))
}

#' Fitted on 850 passes made from within 30 yards of goal in SkillCorner's open
#' A-League 2024/25 tracking, measured to where the intended receiver actually
#' stood (scratch/sc_models.R). Observed completion there was 68%, against
#' 84% and 86% for the two assumed models above. Direction and one-touch
#' added nothing once these three terms were in (LRT p = 0.96).
completion_tracking <- function(pass_length, nearest_defender, lane_blockers = 0, ...) {
  stats::plogis(0.86115 - 0.05744 * pass_length +
                0.22451 * pmin(nearest_defender, 15) - 0.50303 * lane_blockers)
}

COMPLETION_MODELS <- list(
  certain  = completion_certain,
  distance = completion_distance,
  pressure = completion_pressure
)

## Which teammates count as a real alternative to shooting.

pool_ahead <- function(opts, shot) opts
pool_clearly_ahead <- function(opts, shot) opts[opts$pass_length >= 5, , drop = FALSE]
pool_in_box <- function(opts, shot) {
  opts[opts$x >= 102 & opts$y >= 18 & opts$y <= 62, , drop = FALSE]
}

#' Everyone ahead, plus the teammates behind the ball within 15 yards: the
#' lay-off and the cutback the original rule threw away.
pool_with_cutbacks <- function(opts, shot) {
  behind <- if (!is.null(shot) && "behind" %in% names(shot)) shot$behind[[1]] else NULL
  if (is.null(behind) || nrow(behind) == 0) return(opts)
  rbind(opts, behind[, names(opts), drop = FALSE])
}

OPTION_POOLS <- list(
  ahead         = pool_ahead,
  clearly_ahead = pool_clearly_ahead,
  in_box        = pool_in_box
)

## What going wrong is worth. Measured on 3,225 missed open-play shots and
## 2,607 failed passes from shooting range across the 2023 Women's World Cup,
## Leverkusen 23/24 and Euro 2024 (scratch/sweep_models.R): own rebound shots
## and corners won (a corner is worth 0.044 xG) minus what the opponent made
## of the ball next. A missed shot is still worth something, more so up close;
## a failed pass is worth less than a missed shot.
AFTERMATH <- list(
  shot = function(distance, corner_value = CORNER_XG) {
    at <- c(4, 10, 15, 21.5, 30)
    own    <- stats::approx(at, c(0.0417, 0.0222, 0.0170, 0.0085, 0.0034), xout = distance, rule = 2)$y
    corner <- stats::approx(at, c(0.1181, 0.1533, 0.1847, 0.1761, 0.1114), xout = distance, rule = 2)$y
    lost   <- stats::approx(at, c(0.0014, 0.0054, 0.0025, 0.0061, 0.0049), xout = distance, rule = 2)$y
    own + corner * corner_value - lost
  },
  failed_pass = 0.0087
)

## What a corner is worth on average, in xG from the possession it starts.
## A team's own figure can replace it: see scratch/corners.R, which rates the
## attack and the opposing defence from earlier games, weighted by how many of
## today's starters were in them.
CORNER_XG <- 0.044

#' Value of the best available alternative to shooting.
#'
#' Zero when nobody qualifies, which is the honest reading: on the evidence
#' available there was nothing better to do. `offside_rule` drops receivers who
#' would be offside; `aftermath` credits what a miss or a misplaced pass still
#' leads to.
best_alternative <- function(opts, model, completion, use_context = TRUE,
                             offside_rule = FALSE, aftermath = NULL, keeper_x = NA_real_,
                             corner_value = CORNER_XG) {
  if (offside_rule && "offside" %in% names(opts)) opts <- opts[!opts$offside, , drop = FALSE]
  if (nrow(opts) == 0) return(0)
  receive <- shot_value(model, opts$distance, opts$angle,
                        if (use_context) opts$defenders_in_cone else 0, keeper_x,
                        closing_in(opts$nearest_defender, opts$pass_length))
  lanes <- if ("lane_blockers" %in% names(opts)) opts$lane_blockers else 0
  arrive <- completion(opts$pass_length, opts$nearest_defender, lanes)
  if (is.null(aftermath)) return(max(receive * arrive))
  receive <- receive + (1 - receive) * aftermath$shot(opts$distance, corner_value)
  max(arrive * receive + (1 - arrive) * aftermath$failed_pass)
}

#' Score every shot under one fully specified set of choices.
#'
#' Returns the shot table with the chosen shot's value, the best alternative,
#' and the difference. A positive difference means shooting was the better
#' call on these assumptions.
score_shots <- function(shots, model, pool, completion, use_context = TRUE,
                        offside_rule = FALSE, aftermath = NULL, team_corners = FALSE) {
  cv <- if (team_corners && "corner_value" %in% names(shots)) shots$corner_value else rep(CORNER_XG, nrow(shots))
  best <- vapply(seq_len(nrow(shots)), function(i) {
    best_alternative(pool(shots$options[[i]], shots[i, ]), model, completion, use_context,
                     offside_rule, aftermath,
                     if ("keeper_x" %in% names(shots)) shots$keeper_x[i] else NA_real_, cv[i])
  }, numeric(1))
  sv <- shot_value(model, shots$distance, shots$angle,
                   if (use_context) shots$defenders_in_cone else 0,
                   if ("keeper_x" %in% names(shots)) shots$keeper_x else NA_real_,
                   shots$nearest_defender)
  if (!is.null(aftermath)) sv <- sv + (1 - sv) * aftermath$shot(shots$distance, cv)
  shots$shot_value <- sv
  shots$best_alternative <- best
  shots$edge <- shots$shot_value - shots$best_alternative
  shots
}
