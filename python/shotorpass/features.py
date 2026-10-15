"""Turning raw events and freeze frames into one row per shot, with the
positional context needed to ask what else the shooter could have done."""
import numpy as np
import pandas as pd

from .geometry import (forward_visibility, goal_angle, goal_distance, in_shooting_cone,
                       lane_blockers, offside_line, open_goal_share)
from .statsbomb import sb_events, sb_frames, visible_polygon

# Half-width of the goal a keeper covers, in yards, for the open-goal share.
# Kept as a description only: the shot model found no use for it at any reach
# from 0.5 to 3 yards, and uses the keeper's distance off the line instead.
KEEPER_REACH = 1

OPTION_COLUMNS = ["x", "y", "distance", "angle", "defenders_in_cone", "nearest_defender",
                  "pass_length", "lane_blockers", "offside", "open_goal"]


def frame_players(frame):
    """Pull the players out of a freeze frame into a tidy frame."""
    ff = frame.get("freeze_frame") or []
    if not ff:
        return None
    return pd.DataFrame({
        "x": [float(p["location"][0]) for p in ff],
        "y": [float(p["location"][1]) for p in ff],
        "teammate": [p.get("teammate") is True for p in ff],
        "actor": [p.get("actor") is True for p in ff],
        "keeper": [p.get("keeper") is True for p in ff],
    })


def passing_options(players, shot_x, shot_y):
    """Everyone the shooter could have played forward to, with their own geometry.

    A teammate only counts as an option if they are closer to goal than the
    shooter. That was the original rule, and it quietly drops the cutback: see
    `behind_options()` for the teammates it leaves out.
    """
    mates = players[players.teammate & ~players.actor & (players.x > shot_x)]
    return option_table(players, mates, shot_x, shot_y)


def behind_options(players, shot_x, shot_y, within=15):
    """Teammates level with or behind the ball, close enough for a lay-off or a
    cutback. `players.x > shot_x` throws all of these away, yet over half the
    passes that set up a shot from shooting range go backwards."""
    mates = players[players.teammate & ~players.actor & (players.x <= shot_x)]
    mates = mates[np.sqrt((mates.x - shot_x) ** 2 + (mates.y - shot_y) ** 2) <= within]
    return option_table(players, mates, shot_x, shot_y)


def option_table(players, mates, shot_x, shot_y):
    """The measurements taken on each possible receiver."""
    if mates.empty:
        empty = pd.DataFrame({c: pd.Series(dtype=float) for c in OPTION_COLUMNS})
        return empty.astype({"offside": bool})
    opp = players[~players.teammate & ~players.keeper]
    ox, oy = opp.x.to_numpy(), opp.y.to_numpy()
    mx, my = mates.x.to_numpy(), mates.y.to_numpy()
    if len(opp):
        cone = [in_shooting_cone(ox, oy, x, y).sum() for x, y in zip(mx, my)]
        near = [np.sqrt((ox - x) ** 2 + (oy - y) ** 2).min() for x, y in zip(mx, my)]
    else:
        cone = np.zeros(len(mates))
        near = np.full(len(mates), 99.0)
    lane = [lane_blockers(ox, oy, shot_x, shot_y, x, y) for x, y in zip(mx, my)]
    line = offside_line(players.x[~players.teammate], shot_x)
    kx, ky = keeper_of(players)
    return pd.DataFrame({
        "x": mx, "y": my,
        "distance": goal_distance(mx, my),
        "angle": goal_angle(mx, my),
        "defenders_in_cone": np.asarray(cone, dtype=float),
        "nearest_defender": np.asarray(near, dtype=float),
        "pass_length": np.sqrt((mx - shot_x) ** 2 + (my - shot_y) ** 2),
        "lane_blockers": np.asarray(lane, dtype=float),
        "offside": mx > line,
        "open_goal": open_goal_share(mx, my, kx, ky, KEEPER_REACH),
    })


def keeper_of(players):
    """Where the opposing keeper is, or NaN if the camera missed them."""
    k = players[~players.teammate & players.keeper]
    if k.empty:
        return np.nan, np.nan
    return k.x.iloc[0], k.y.iloc[0]


def _name(d):
    return (d or {}).get("name")


def shots_for_match(match_id):
    """Build the shot table for a single match.

    Penalties are dropped. They are a different game with no passing option and
    they would dominate any model of shot value.
    """
    events = sb_events(match_id)
    frames = sb_frames(match_id)

    rows, options, behind = [], [], []
    for e in events:
        if _name(e.get("type")) != "Shot":
            continue
        shot = e.get("shot") or {}
        if _name(shot.get("type")) == "Penalty":
            continue
        fr = frames.get(e["id"])
        if fr is None:
            continue
        players = frame_players(fr)
        if players is None:
            continue

        x, y = float(e["location"][0]), float(e["location"][1])
        opp = players[~players.teammate & ~players.keeper]
        kx, ky = keeper_of(players)
        rows.append({
            "match_id": match_id,
            "shot_id": e["id"],
            "team": e["team"]["name"],
            "player": _name(e.get("player")),
            "minute": e["minute"],
            "x": x, "y": y,
            "distance": goal_distance(x, y),
            "angle": goal_angle(x, y),
            "defenders_in_cone": int(in_shooting_cone(opp.x, opp.y, x, y).sum()) if len(opp) else 0,
            "nearest_defender": np.sqrt((opp.x - x) ** 2 + (opp.y - y) ** 2).min() if len(opp) else 99.0,
            "players_seen": len(players),
            "forward_visible": forward_visibility(visible_polygon(fr), x),
            "body_part": _name(shot.get("body_part")),
            "play_pattern": _name(e.get("play_pattern")),
            "statsbomb_xg": shot.get("statsbomb_xg", 0.0),
            "goal": int(_name(shot.get("outcome")) == "Goal"),
            "shot_type": _name(shot.get("type")),
            "first_time": shot.get("first_time") is True,
            "keeper_x": kx, "keeper_y": ky,
            "open_goal": float(open_goal_share(x, y, kx, ky, KEEPER_REACH)),
        })
        options.append(passing_options(players, x, y))
        behind.append(behind_options(players, x, y))
    if not rows:
        return None
    shots = pd.DataFrame(rows)
    shots["options"] = pd.Series(options, dtype=object)
    shots["behind"] = pd.Series(behind, dtype=object)
    return shots


def build_shots(match_ids, verbose=True):
    """Build the shot table across every match in the tournament."""
    out = []
    for i, match_id in enumerate(match_ids, 1):
        out.append(shots_for_match(match_id))
        if verbose:
            print(f"\r{i}/{len(match_ids)} matches", end="")
    if verbose:
        print()
    return pd.concat([s for s in out if s is not None], ignore_index=True)
