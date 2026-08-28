## Turning raw events and freeze frames into one row per shot, with the
## positional context needed to ask what else the shooter could have done.

#' Pull the players out of a freeze frame into a tidy frame.
frame_players <- function(frame) {
  ff <- frame$freeze_frame
  if (length(ff) == 0) return(NULL)
  data.frame(
    x        = vapply(ff, function(p) p$location[[1]], numeric(1)),
    y        = vapply(ff, function(p) p$location[[2]], numeric(1)),
    teammate = vapply(ff, function(p) isTRUE(p$teammate), logical(1)),
    actor    = vapply(ff, function(p) isTRUE(p$actor), logical(1)),
    keeper   = vapply(ff, function(p) isTRUE(p$keeper), logical(1))
  )
}

#' Everyone the shooter could have played forward to, with their own geometry.
#'
#' A teammate only counts as an option if they are closer to goal than the
#' shooter. Square and backward passes are not alternatives to shooting.
passing_options <- function(players, shot_x, shot_y) {
  opp   <- players[!players$teammate & !players$keeper, ]
  mates <- players[players$teammate & !players$actor & players$x > shot_x, ]
  if (nrow(mates) == 0) {
    return(data.frame(x = numeric(0), y = numeric(0), distance = numeric(0),
                      angle = numeric(0), defenders_in_cone = numeric(0),
                      nearest_defender = numeric(0), pass_length = numeric(0)))
  }
  cone <- vapply(seq_len(nrow(mates)), function(i) {
    if (nrow(opp) == 0) return(0)
    sum(in_shooting_cone(opp$x, opp$y, mates$x[i], mates$y[i]))
  }, numeric(1))
  near <- vapply(seq_len(nrow(mates)), function(i) {
    if (nrow(opp) == 0) return(99)
    min(sqrt((opp$x - mates$x[i])^2 + (opp$y - mates$y[i])^2))
  }, numeric(1))
  data.frame(
    x = mates$x, y = mates$y,
    distance = goal_distance(mates$x, mates$y),
    angle    = goal_angle(mates$x, mates$y),
    defenders_in_cone = cone,
    nearest_defender  = near,
    pass_length = sqrt((mates$x - shot_x)^2 + (mates$y - shot_y)^2)
  )
}

#' Build the shot table for a single match.
#'
#' Penalties are dropped. They are a different game with no passing option and
#' they would dominate any model of shot value.
shots_for_match <- function(match_id) {
  events <- sb_events(match_id)
  frames <- sb_frames(match_id)

  rows <- list()
  for (e in events) {
    if (is.null(e$type$name) || e$type$name != "Shot") next
    if (identical(e$shot$type$name, "Penalty")) next
    fr <- frames[[e$id]]
    if (is.null(fr)) next
    players <- frame_players(fr)
    if (is.null(players)) next

    loc <- unlist(e$location)
    opp <- players[!players$teammate & !players$keeper, ]
    opts <- passing_options(players, loc[1], loc[2])
    poly <- visible_polygon(fr)

    rows[[length(rows) + 1]] <- data.frame(
      match_id  = match_id,
      shot_id   = e$id,
      team      = e$team$name,
      player    = if (is.null(e$player$name)) NA_character_ else e$player$name,
      minute    = e$minute,
      x = loc[1], y = loc[2],
      distance  = goal_distance(loc[1], loc[2]),
      angle     = goal_angle(loc[1], loc[2]),
      defenders_in_cone = if (nrow(opp)) sum(in_shooting_cone(opp$x, opp$y, loc[1], loc[2])) else 0,
      nearest_defender  = if (nrow(opp)) min(sqrt((opp$x - loc[1])^2 + (opp$y - loc[2])^2)) else 99,
      players_seen      = nrow(players),
      forward_visible   = forward_visibility(poly, loc[1]),
      body_part   = if (is.null(e$shot$body_part$name)) NA_character_ else e$shot$body_part$name,
      play_pattern = if (is.null(e$play_pattern$name)) NA_character_ else e$play_pattern$name,
      statsbomb_xg = if (is.null(e$shot$statsbomb_xg)) 0 else e$shot$statsbomb_xg,
      goal = as.integer(identical(e$shot$outcome$name, "Goal")),
      stringsAsFactors = FALSE
    )
    rows[[length(rows)]]$options <- I(list(opts))
  }
  if (length(rows) == 0) return(NULL)
  do.call(rbind, rows)
}

#' Build the shot table across every match in the tournament.
build_shots <- function(match_ids, verbose = TRUE) {
  out <- vector("list", length(match_ids))
  for (i in seq_along(match_ids)) {
    out[[i]] <- shots_for_match(match_ids[i])
    if (verbose) cat(sprintf("\r%d/%d matches", i, length(match_ids)))
  }
  if (verbose) cat("\n")
  do.call(rbind, out)
}
