## Pitch geometry. StatsBomb coordinates run 0-120 along the pitch and 0-80
## across it, with the attacking goal always at x = 120.

PITCH_LENGTH <- 120
PITCH_WIDTH  <- 80
GOAL_X       <- 120
GOAL_Y       <- 40
POST_LEFT    <- 36
POST_RIGHT   <- 44

#' Straight-line distance from a point to the centre of the goal.
goal_distance <- function(x, y) {
  sqrt((GOAL_X - x)^2 + (GOAL_Y - y)^2)
}

#' The angle the goalmouth subtends at a point, in radians.
#'
#' A shot from the penalty spot sees a much wider goal than one from the
#' touchline at the same distance, which is why this matters more than
#' distance on its own.
goal_angle <- function(x, y) {
  a <- atan2(POST_LEFT - y, GOAL_X - x)
  b <- atan2(POST_RIGHT - y, GOAL_X - x)
  abs(b - a)
}

#' Is a point inside the triangle formed by a shooter and the two posts?
#'
#' Vectorised over px, py. Used to count how many defenders are actually
#' between the ball and the goal rather than merely nearby.
in_shooting_cone <- function(px, py, shot_x, shot_y) {
  cross <- function(ax, ay, bx, by, cx, cy) (ax - cx) * (by - cy) - (bx - cx) * (ay - cy)
  d1 <- cross(px, py, shot_x, shot_y, GOAL_X, POST_LEFT)
  d2 <- cross(px, py, GOAL_X, POST_LEFT, GOAL_X, POST_RIGHT)
  d3 <- cross(px, py, GOAL_X, POST_RIGHT, shot_x, shot_y)
  neg <- d1 < 0 | d2 < 0 | d3 < 0
  pos <- d1 > 0 | d2 > 0 | d3 > 0
  !(neg & pos)
}

#' Share of the goalmouth the keeper leaves open, seen from a point.
#'
#' The keeper is treated as a body `reach` yards either side of where they
#' stand, square on to the player. Whatever part of the goal's angle that body
#' covers is closed; the rest is what a shot could actually go into. A keeper
#' who has come out to the shooter closes most of the goal for the shooter and
#' very little of it for a teammate square of them, which is the whole point.
#' Vectorised over px, py. NA keeper coordinates give NA.
open_goal_share <- function(px, py, kx, ky, reach = 1) {
  a <- atan2(POST_LEFT - py, GOAL_X - px)
  b <- atan2(POST_RIGHT - py, GOAL_X - px)
  lo <- pmin(a, b)
  hi <- pmax(a, b)
  kd <- sqrt((kx - px)^2 + (ky - py)^2)
  ka <- atan2(ky - py, kx - px)
  half <- atan(reach / pmax(kd, reach))
  blocked <- pmax(0, pmin(hi, ka + half) - pmax(lo, ka - half))
  blocked <- ifelse(kx <= px, 0, blocked)
  (hi - lo - blocked) / (hi - lo)
}

#' How many opponents stand in the lane of a pass.
#'
#' An opponent counts if they are within `width` yards of the straight line
#' from the ball to the receiver, somewhere between the first and last tenth of
#' it. Standing right on top of the passer or the receiver is pressure, which
#' is measured separately.
lane_blockers <- function(opp_x, opp_y, x0, y0, x1, y1, width = 1.5) {
  if (length(opp_x) == 0) return(0L)
  dx <- x1 - x0
  dy <- y1 - y0
  L2 <- dx^2 + dy^2
  if (L2 == 0) return(0L)
  t <- ((opp_x - x0) * dx + (opp_y - y0) * dy) / L2
  d <- sqrt((opp_x - (x0 + t * dx))^2 + (opp_y - (y0 + t * dy))^2)
  sum(t >= 0.1 & t <= 0.9 & d <= width)
}

#' The x position beyond which a receiver would be offside.
#'
#' Level with or behind the ball is onside, and so is anyone not past the
#' second-last opponent, the keeper usually being the last. Only the opponents
#' the camera caught can be checked, so a defender off screen can make a
#' receiver who was onside look offside.
offside_line <- function(opp_x, ball_x) {
  second_last <- if (length(opp_x) >= 2) sort(opp_x, decreasing = TRUE)[2] else -Inf
  max(second_last, ball_x, PITCH_LENGTH / 2)
}

#' Area of a simple polygon given as a two column matrix of vertices.
polygon_area <- function(pts) {
  n <- nrow(pts)
  if (n < 3) return(0)
  j <- c(seq_len(n)[-1], 1L)
  abs(sum(pts[, 1] * pts[j, 2] - pts[j, 1] * pts[, 2])) / 2
}

#' Clip a polygon to the half plane x >= cut, Sutherland-Hodgman.
#'
#' The camera only shows part of the pitch. To ask how much of the area *ahead
#' of a shooter* was on screen, the visible polygon has to be cut at that x
#' position first.
clip_to_halfplane <- function(pts, cut) {
  n <- nrow(pts)
  if (n < 3) return(pts[0, , drop = FALSE])
  out <- vector("list", 2 * n)
  k <- 0
  for (i in seq_len(n)) {
    cur  <- pts[i, ]
    prev <- pts[if (i == 1) n else i - 1, ]
    cur_in  <- cur[1]  >= cut
    prev_in <- prev[1] >= cut
    if (cur_in != prev_in) {
      t <- if (cur[1] == prev[1]) 0 else (cut - prev[1]) / (cur[1] - prev[1])
      k <- k + 1
      out[[k]] <- c(cut, prev[2] + t * (cur[2] - prev[2]))
    }
    if (cur_in) {
      k <- k + 1
      out[[k]] <- cur
    }
  }
  if (k == 0) return(pts[0, , drop = FALSE])
  do.call(rbind, out[seq_len(k)])
}

#' Share of the pitch ahead of a shooter that fell inside the camera view.
#'
#' Returns NA where the shot is so close to goal that the forward area is
#' negligible and the ratio stops meaning anything.
forward_visibility <- function(visible_pts, shot_x) {
  total <- (GOAL_X - shot_x) * PITCH_WIDTH
  if (total <= 1) return(NA_real_)
  seen <- polygon_area(clip_to_halfplane(visible_pts, shot_x))
  min(seen / total, 1)
}
