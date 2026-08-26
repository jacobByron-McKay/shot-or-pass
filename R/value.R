## What a shot was worth, and what the best thing she could have done instead
## was worth.

#' Fit a shot value model on the tournament's own shots.
#'
#' Three terms, all readable. Distance and goalmouth angle are the standard
#' pair. Bodies in the shooting cone is the term that only exists because of
#' the freeze frames, and it is the one that earns its place.
fit_shot_value <- function(shots, context = TRUE) {
  f <- if (context) goal ~ distance + angle + defenders_in_cone
       else         goal ~ distance + angle
  stats::glm(f, family = stats::binomial, data = shots)
}

#' Apply a fitted shot model to arbitrary positions.
shot_value <- function(model, distance, angle, defenders_in_cone = 0) {
  nd <- data.frame(distance = distance, angle = angle,
                   defenders_in_cone = defenders_in_cone)
  as.numeric(stats::predict(model, nd, type = "response"))
}

## Three defensible views of how likely a pass is to arrive. Every one of these
## is an assumption somebody would defend in a meeting, and none of them is
## written down in the analyses that rely on them.

completion_certain <- function(pass_length, nearest_defender) {
  rep(1, length(pass_length))
}

completion_distance <- function(pass_length, nearest_defender) {
  stats::plogis(2.6 - 0.06 * pass_length)
}

completion_pressure <- function(pass_length, nearest_defender) {
  stats::plogis(2.2 - 0.055 * pass_length + 0.10 * pmin(nearest_defender, 15))
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

OPTION_POOLS <- list(
  ahead         = pool_ahead,
  clearly_ahead = pool_clearly_ahead,
  in_box        = pool_in_box
)

#' Value of the best available alternative to shooting.
#'
#' Zero when nobody qualifies, which is the honest reading: on the evidence
#' available there was nothing better to do.
best_alternative <- function(opts, model, completion, use_context = TRUE) {
  if (nrow(opts) == 0) return(0)
  receive <- shot_value(model, opts$distance, opts$angle,
                        if (use_context) opts$defenders_in_cone else 0)
  arrive <- completion(opts$pass_length, opts$nearest_defender)
  max(receive * arrive)
}

#' Score every shot under one fully specified set of choices.
#'
#' Returns the shot table with the chosen shot's value, the best alternative,
#' and the difference. A positive difference means shooting was the better
#' call on these assumptions.
score_shots <- function(shots, model, pool, completion, use_context = TRUE) {
  best <- vapply(seq_len(nrow(shots)), function(i) {
    best_alternative(pool(shots$options[[i]], shots[i, ]), model, completion, use_context)
  }, numeric(1))
  shots$shot_value <- shot_value(model, shots$distance, shots$angle,
                                 if (use_context) shots$defenders_in_cone else 0)
  shots$best_alternative <- best
  shots$edge <- shots$shot_value - shots$best_alternative
  shots
}
