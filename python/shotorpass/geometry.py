"""Pitch geometry. StatsBomb coordinates run 0-120 along the pitch and 0-80
across it, with the attacking goal always at x = 120."""
import math

import numpy as np

PITCH_LENGTH = 120
PITCH_WIDTH = 80
GOAL_X = 120
GOAL_Y = 40
POST_LEFT = 36
POST_RIGHT = 44


def goal_distance(x, y):
    """Straight-line distance from a point to the centre of the goal."""
    return np.sqrt((GOAL_X - np.asarray(x)) ** 2 + (GOAL_Y - np.asarray(y)) ** 2)


def goal_angle(x, y):
    """The angle the goalmouth subtends at a point, in radians.

    A shot from the penalty spot sees a much wider goal than one from the
    touchline at the same distance, which is why this matters more than
    distance on its own.
    """
    x, y = np.asarray(x), np.asarray(y)
    a = np.arctan2(POST_LEFT - y, GOAL_X - x)
    b = np.arctan2(POST_RIGHT - y, GOAL_X - x)
    return np.abs(b - a)


def in_shooting_cone(px, py, shot_x, shot_y):
    """Is a point inside the triangle formed by a shooter and the two posts?

    Vectorised over px, py. Used to count how many defenders are actually
    between the ball and the goal rather than merely nearby.
    """
    px, py = np.asarray(px), np.asarray(py)

    def cross(ax, ay, bx, by, cx, cy):
        return (ax - cx) * (by - cy) - (bx - cx) * (ay - cy)

    d1 = cross(px, py, shot_x, shot_y, GOAL_X, POST_LEFT)
    d2 = cross(px, py, GOAL_X, POST_LEFT, GOAL_X, POST_RIGHT)
    d3 = cross(px, py, GOAL_X, POST_RIGHT, shot_x, shot_y)
    neg = (d1 < 0) | (d2 < 0) | (d3 < 0)
    pos = (d1 > 0) | (d2 > 0) | (d3 > 0)
    return ~(neg & pos)


def open_goal_share(px, py, kx, ky, reach=1):
    """Share of the goalmouth the keeper leaves open, seen from a point.

    The keeper is treated as a body `reach` yards either side of where they
    stand, square on to the player. Whatever part of the goal's angle that body
    covers is closed; the rest is what a shot could actually go into. A keeper
    who has come out to the shooter closes most of the goal for the shooter and
    very little of it for a teammate square of them, which is the whole point.
    Vectorised over px, py. A NaN keeper gives NaN.
    """
    px, py = np.asarray(px, dtype=float), np.asarray(py, dtype=float)
    kx, ky = np.asarray(kx, dtype=float), np.asarray(ky, dtype=float)
    a = np.arctan2(POST_LEFT - py, GOAL_X - px)
    b = np.arctan2(POST_RIGHT - py, GOAL_X - px)
    lo = np.minimum(a, b)
    hi = np.maximum(a, b)
    kd = np.sqrt((kx - px) ** 2 + (ky - py) ** 2)
    ka = np.arctan2(ky - py, kx - px)
    half = np.arctan(reach / np.maximum(kd, reach))
    blocked = np.maximum(0, np.minimum(hi, ka + half) - np.maximum(lo, ka - half))
    # a keeper level with or behind the player covers none of the goal; NaN
    # compares False, so a missing keeper keeps its NaN
    blocked = np.where(kx <= px, 0.0, blocked)
    return (hi - lo - blocked) / (hi - lo)


def lane_blockers(opp_x, opp_y, x0, y0, x1, y1, width=1.5):
    """How many opponents stand in the lane of a pass.

    An opponent counts if they are within `width` yards of the straight line
    from the ball to the receiver, somewhere between the first and last tenth of
    it. Standing right on top of the passer or the receiver is pressure, which
    is measured separately.
    """
    opp_x, opp_y = np.asarray(opp_x, dtype=float), np.asarray(opp_y, dtype=float)
    if opp_x.size == 0:
        return 0
    dx = x1 - x0
    dy = y1 - y0
    L2 = dx ** 2 + dy ** 2
    if L2 == 0:
        return 0
    t = ((opp_x - x0) * dx + (opp_y - y0) * dy) / L2
    d = np.sqrt((opp_x - (x0 + t * dx)) ** 2 + (opp_y - (y0 + t * dy)) ** 2)
    return int(np.sum((t >= 0.1) & (t <= 0.9) & (d <= width)))


def offside_line(opp_x, ball_x):
    """The x position beyond which a receiver would be offside.

    Level with or behind the ball is onside, and so is anyone not past the
    second-last opponent, the keeper usually being the last. Only the opponents
    the camera caught can be checked, so a defender off screen can make a
    receiver who was onside look offside.
    """
    xs = sorted(opp_x, reverse=True)
    second_last = xs[1] if len(xs) >= 2 else -np.inf
    return max(second_last, ball_x, PITCH_LENGTH / 2)


def polygon_area(pts):
    """Area of a simple polygon given as an (n, 2) array of vertices."""
    pts = np.asarray(pts, dtype=float)
    if len(pts) < 3:
        return 0.0
    nxt = np.roll(pts, -1, axis=0)
    # fsum, not np.sum: R's sum() accumulates in extended precision, and plain
    # double summation drifts from it in the last bits
    return abs(math.fsum(pts[:, 0] * nxt[:, 1] - nxt[:, 0] * pts[:, 1])) / 2


def clip_to_halfplane(pts, cut):
    """Clip a polygon to the half plane x >= cut, Sutherland-Hodgman.

    The camera only shows part of the pitch. To ask how much of the area *ahead
    of a shooter* was on screen, the visible polygon has to be cut at that x
    position first.
    """
    pts = np.asarray(pts, dtype=float)
    n = len(pts)
    if n < 3:
        return np.empty((0, 2))
    out = []
    for i in range(n):
        cur, prev = pts[i], pts[i - 1]
        cur_in, prev_in = cur[0] >= cut, prev[0] >= cut
        if cur_in != prev_in:
            t = 0 if cur[0] == prev[0] else (cut - prev[0]) / (cur[0] - prev[0])
            out.append((cut, prev[1] + t * (cur[1] - prev[1])))
        if cur_in:
            out.append((cur[0], cur[1]))
    return np.array(out) if out else np.empty((0, 2))


def forward_visibility(visible_pts, shot_x):
    """Share of the pitch ahead of a shooter that fell inside the camera view.

    NaN where the shot is so close to goal that the forward area is negligible
    and the ratio stops meaning anything.
    """
    total = (GOAL_X - shot_x) * PITCH_WIDTH
    if total <= 1:
        return np.nan
    seen = polygon_area(clip_to_halfplane(visible_pts, shot_x))
    return min(seen / total, 1.0)
