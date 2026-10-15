"""What a shot was worth, and what the best thing the player could have done
instead was worth."""
import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy.special import expit

from .geometry import GOAL_X

# How far off the line the keeper usually is (median across the tournament's
# shots, 2.4 yards). Frames without a keeper get this plus a flag, so the
# model learns what an unseen keeper is worth instead of being told.
KEEPER_OFF_LINE_TYPICAL = 2.4

# Space: yards to the nearest outfield defender, capped where it stops
# mattering. Worth +0.22 a yard on the tournament's shots (p = 0.0005) and
# +0.18 across 33,000 women's shots, on top of every other term.
SPACE_CAP = 10


def fit_shot_value(shots, context=True, keeper=False, space=False):
    """Fit a shot value model on the tournament's own shots.

    Three terms, all readable. Distance and goalmouth angle are the standard
    pair. Bodies in the shooting cone is the term that only exists because of
    the freeze frames, and it is the one that earns its place. `keeper=True`
    adds how far the keeper stands off the goal line, plus a flag for frames
    where the camera missed the keeper.

    Why distance off the line and not the share of the goal the keeper leaves
    open: both were tried on the tournament's shots. Off the line improves the
    model (AIC down 12.3, p < 0.0001; goals roughly double once the keeper is
    four yards out). The open-goal geometry does nothing (p = 0.74) and neither
    does standing sideways out of position (p = 0.41). A keeper who has come a
    long way out is usually a keeper who has been caught, not one covering the
    angle better.
    """
    f = "goal ~ distance + angle + defenders_in_cone" if context else "goal ~ distance + angle"
    if keeper:
        shots = with_keeper_terms(shots)
        f += " + keeper_off_line + keeper_missing"
    if space:
        shots = shots.assign(space=np.minimum(shots["nearest_defender"], SPACE_CAP))
        f += " + space"
    return smf.glm(f, data=shots, family=sm.families.Binomial()).fit()


def closing_in(space_at_pass, pass_length):
    """The space a receiver will have when they shoot, not when the pass leaves.

    Two stages, both measured on SkillCorner's A-League tracking. While the ball
    travels (about 12.3 yards a second) a receiver with room loses some of it:
    seven to twelve yards becomes about four to eight, and a player already tight
    stays tight (1,137 completed passes, scratch/sc_closing.py). Then, between the
    first touch and the shot, defenders keep coming: 325 receptions that became
    shots went from a median 4.7 yards to 2.5 when a touch was taken
    (scratch/sc_receive_to_shot.py). The shooter's own space is measured at the
    shot, so this puts both sides of the comparison at the same moment.
    """
    s = np.asarray(space_at_pass, dtype=float)
    t = np.asarray(pass_length, dtype=float) / 12.3
    on_receipt = 0.652 + 0.647 * s + 0.209 * t - 0.044 * s * t
    return np.minimum(1.808 + 0.256 * on_receipt, SPACE_CAP)


def shot_value(model, distance, angle, defenders_in_cone=0, keeper_x=np.nan, space=SPACE_CAP):
    """Apply a fitted shot model to arbitrary positions.

    `keeper_x` is where the keeper stood in the frame, the same for the shooter
    and every teammate in it. NaN means the camera did not catch them. `space`
    only counts if the model was fitted with it.
    """
    nd = pd.DataFrame({"distance": np.atleast_1d(distance), "angle": np.atleast_1d(angle)})
    nd["defenders_in_cone"] = defenders_in_cone if np.ndim(defenders_in_cone) == 0 \
        else np.asarray(defenders_in_cone)
    if "space" in model.params.index:
        sp = np.broadcast_to(np.asarray(space, dtype=float), len(nd))
        nd["space"] = np.minimum(sp, SPACE_CAP)
    if "keeper_off_line" in model.params.index:
        kx = np.broadcast_to(np.asarray(keeper_x, dtype=float), len(nd))
        nd["keeper_missing"] = np.isnan(kx).astype(float)
        nd["keeper_off_line"] = np.where(np.isnan(kx), KEEPER_OFF_LINE_TYPICAL, GOAL_X - kx)
    return np.asarray(model.predict(nd))


def with_keeper_terms(shots):
    shots = shots.copy()
    missing = shots["keeper_x"].isna()
    shots["keeper_missing"] = missing.astype(float)
    shots["keeper_off_line"] = np.where(missing, KEEPER_OFF_LINE_TYPICAL, GOAL_X - shots["keeper_x"])
    return shots


# Defensible views of how likely a pass is to arrive. The first three are
# assumptions somebody would defend in a meeting, and none of them is written
# down in the analyses that rely on them. The fourth is measured.

def completion_certain(pass_length, nearest_defender, *_):
    return np.ones(np.size(pass_length))


def completion_distance(pass_length, nearest_defender, *_):
    return expit(2.6 - 0.06 * np.asarray(pass_length))


def completion_pressure(pass_length, nearest_defender, *_):
    return expit(2.2 - 0.055 * np.asarray(pass_length)
                 + 0.10 * np.minimum(nearest_defender, 15))


def completion_tracking(pass_length, nearest_defender, lane_blockers=0, *_):
    """Fitted on 850 passes made from within 30 yards of goal in SkillCorner's open
    A-League 2024/25 tracking, measured to where the intended receiver actually
    stood (scratch/sc_models.R). Observed completion there was 68%, against
    84% and 86% for the two assumed models above. Direction and one-touch
    added nothing once these three terms were in (LRT p = 0.96)."""
    return expit(0.86115 - 0.05744 * np.asarray(pass_length)
                 + 0.22451 * np.minimum(nearest_defender, 15)
                 - 0.50303 * np.asarray(lane_blockers))


COMPLETION_MODELS = {
    "certain": completion_certain,
    "distance": completion_distance,
    "pressure": completion_pressure,
}


# Which teammates count as a real alternative to shooting.

def pool_ahead(opts, shot=None):
    return opts


def pool_clearly_ahead(opts, shot=None):
    return opts[opts.pass_length >= 5]


def pool_in_box(opts, shot=None):
    return opts[(opts.x >= 102) & (opts.y >= 18) & (opts.y <= 62)]


def pool_with_cutbacks(opts, shot=None):
    """Everyone ahead, plus the teammates behind the ball within 15 yards: the
    lay-off and the cutback the original rule threw away."""
    behind = shot["behind"] if shot is not None and "behind" in shot.index else None
    if behind is None or behind.empty:
        return opts
    return pd.concat([opts, behind[opts.columns]], ignore_index=True)


OPTION_POOLS = {
    "ahead": pool_ahead,
    "clearly_ahead": pool_clearly_ahead,
    "in_box": pool_in_box,
}


# What a corner is worth on average, in xG from the possession it starts.
# A team's own figure can replace it: see scratch/corners.R, which rates the
# attack and the opposing defence from earlier games, weighted by how many of
# today's starters were in them.
CORNER_XG = 0.044


def aftermath_shot(distance, corner_value=CORNER_XG):
    at = [4, 10, 15, 21.5, 30]
    own = np.interp(distance, at, [0.0417, 0.0222, 0.0170, 0.0085, 0.0034])
    corner = np.interp(distance, at, [0.1181, 0.1533, 0.1847, 0.1761, 0.1114])
    lost = np.interp(distance, at, [0.0014, 0.0054, 0.0025, 0.0061, 0.0049])
    return own + corner * corner_value - lost


# What going wrong is worth. Measured on 3,225 missed open-play shots and
# 2,607 failed passes from shooting range across the 2023 Women's World Cup,
# Leverkusen 23/24 and Euro 2024 (scratch/sweep_models.R): own rebound shots
# and corners won (a corner is worth 0.044 xG) minus what the opponent made
# of the ball next. A missed shot is still worth something, more so up close;
# a failed pass is worth less than a missed shot.
AFTERMATH = {"shot": aftermath_shot, "failed_pass": 0.0087}


def best_alternative(opts, model, completion, use_context=True, offside_rule=False,
                     aftermath=None, keeper_x=np.nan, corner_value=CORNER_XG):
    """Value of the best available alternative to shooting.

    Zero when nobody qualifies, which is the honest reading: on the evidence
    available there was nothing better to do. `offside_rule` drops receivers who
    would be offside; `aftermath` credits what a miss or a misplaced pass still
    leads to.
    """
    if offside_rule and "offside" in opts:
        opts = opts[~opts.offside]
    if opts.empty:
        return 0.0
    receive = shot_value(model, opts.distance, opts.angle,
                         opts.defenders_in_cone if use_context else 0, keeper_x,
                         closing_in(opts.nearest_defender, opts.pass_length))
    lanes = opts.lane_blockers.to_numpy() if "lane_blockers" in opts else 0
    arrive = completion(opts.pass_length.to_numpy(), opts.nearest_defender.to_numpy(), lanes)
    if aftermath is None:
        return float(np.max(receive * arrive))
    receive = receive + (1 - receive) * aftermath["shot"](opts.distance.to_numpy(), corner_value)
    return float(np.max(arrive * receive + (1 - arrive) * aftermath["failed_pass"]))


def score_shots(shots, model, pool, completion, use_context=True, offside_rule=False,
                aftermath=None, team_corners=False):
    """Score every shot under one fully specified set of choices.

    Returns the shot table with the chosen shot's value, the best alternative,
    and the difference. A positive difference means shooting was the better
    call on these assumptions.
    """
    keeper_x = shots["keeper_x"].to_numpy() if "keeper_x" in shots else np.full(len(shots), np.nan)
    if team_corners and "corner_value" in shots:
        cv = shots["corner_value"].to_numpy()
    else:
        cv = np.full(len(shots), CORNER_XG)
    best = [
        best_alternative(pool(shots["options"].iat[i], shots.iloc[i]), model, completion,
                         use_context, offside_rule, aftermath, keeper_x[i], cv[i])
        for i in range(len(shots))
    ]
    sv = shot_value(model, shots["distance"], shots["angle"],
                    shots["defenders_in_cone"] if use_context else 0, keeper_x,
                    shots["nearest_defender"].to_numpy())
    if aftermath is not None:
        sv = sv + (1 - sv) * aftermath["shot"](shots["distance"].to_numpy(), cv)
    return shots.assign(shot_value=sv, best_alternative=best, edge=sv - np.asarray(best))
