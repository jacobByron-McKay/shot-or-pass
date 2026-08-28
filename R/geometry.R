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
