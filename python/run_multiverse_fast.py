"""The 36 and the 96 again, written the way numpy and pandas want them
written. The Python counterpart of analysis/06-multiverse-fast.R.

score_shots() walks the shots one at a time and asks statsmodels what each
shot's receivers are worth, about 140,000 predict() calls over the two
multiverses, and every one of them sends its rows back through patsy. Here
every option for every shot sits in one long table, a specification is a few
array operations over it, and the best option for each shot is a grouped
maximum.

    python run_multiverse_fast.py    # after build_shots.py and run_multiverse.py
"""
import time

import numpy as np
import pandas as pd

from run_multiverse import with_team_corners
from shotorpass.geometry import GOAL_X
from shotorpass.multiverse import multiverse
from shotorpass.statsbomb import ROOT
from shotorpass.value import (AFTERMATH, COMPLETION_MODELS, CORNER_XG, KEEPER_OFF_LINE_TYPICAL,
                              OPTION_POOLS, SPACE_CAP, closing_in, completion_distance,
                              completion_pressure, completion_tracking, fit_shot_value,
                              pool_ahead, pool_clearly_ahead, pool_in_box)

CACHE = ROOT / "cache" / "shots_py.pkl"
REPORTS = ROOT / "reports"
timings = {}


def long_options(shots):
    """Every option for every shot in one table, a row per possible receiver.

    `shot` is the position of the shot the option belongs to. `behind` marks
    the lay-offs and cutbacks, which only the cutback pool lets in. `space` is
    the room the receiver will have left by the time they shoot.
    """
    parts = []
    for col, behind in [("options", False), ("behind", True)]:
        d = pd.concat(list(shots[col]), ignore_index=True)
        d["shot"] = np.repeat(np.arange(len(shots)), shots[col].map(len).to_numpy())
        d["behind"] = behind
        parts.append(d)
    opts = pd.concat(parts, ignore_index=True)
    opts["keeper_x"] = shots["keeper_x"].to_numpy()[opts["shot"]]
    opts["space"] = closing_in(opts["nearest_defender"], opts["pass_length"])
    return opts


def model_value(model, d, use_context=True, space=SPACE_CAP):
    """What the fitted model says each row is worth, straight from its coefficients.

    The design matrix predict() rebuilds through patsy on every call, built
    once for the whole table. A model fitted without a term never reads its
    column.
    """
    kx = d["keeper_x"].to_numpy()
    unseen = np.isnan(kx)
    terms = {
        "Intercept": np.ones(len(d)),
        "distance": d["distance"].to_numpy(dtype=float),
        "angle": d["angle"].to_numpy(dtype=float),
        "defenders_in_cone": (d["defenders_in_cone"].to_numpy(dtype=float) if use_context
                              else np.zeros(len(d))),
        "keeper_off_line": np.where(unseen, KEEPER_OFF_LINE_TYPICAL, GOAL_X - kx),
        "keeper_missing": unseen.astype(float),
        "space": np.minimum(np.broadcast_to(np.asarray(space, dtype=float), len(d)), SPACE_CAP),
    }
    X = np.column_stack([terms[t] for t in model.params.index])
    return model.family.link.inverse(X @ model.params.to_numpy())


# The option pools from shotorpass.value as filters on the long table. The
# first three only look at teammates ahead of the ball; with cutbacks, everyone.
LONG_POOLS = {
    "ahead": lambda o: pool_ahead(o[~o["behind"]]),
    "clearly_ahead": lambda o: pool_clearly_ahead(o[~o["behind"]]),
    "in_box": lambda o: pool_in_box(o[~o["behind"]]),
    "with_cutbacks": lambda o: o,
}


def score_long(shots, opts, model, pool, completion, use_context=True, offside_rule=False,
               aftermath=None, team_corners=False):
    """Score every shot under one specification, all shots at once.

    The arithmetic of score_shots() and best_alternative(), unchanged. Every
    shot's best alternative starts at zero, which is also the answer for a shot
    with nobody left in the pool; no option is worth less than that. Receivers
    are valued on the space they will have once defenders close in, the
    shooter on the space they had.
    """
    cv = shots["corner_value"].to_numpy() if team_corners else np.full(len(shots), CORNER_XG)
    o = pool(opts)
    if offside_rule:
        o = o[~o["offside"]]
    shot = o["shot"].to_numpy()
    receive = model_value(model, o, use_context, o["space"].to_numpy())
    arrive = completion(o["pass_length"].to_numpy(), o["nearest_defender"].to_numpy(),
                        o["lane_blockers"].to_numpy())
    if aftermath is None:
        value = receive * arrive
    else:
        receive = receive + (1 - receive) * aftermath["shot"](o["distance"].to_numpy(), cv[shot])
        value = arrive * receive + (1 - arrive) * aftermath["failed_pass"]
    best = np.zeros(len(shots))
    np.maximum.at(best, shot, value)

    sv = model_value(model, shots, use_context, shots["nearest_defender"].to_numpy())
    if aftermath is not None:
        sv = sv + (1 - sv) * aftermath["shot"](shots["distance"].to_numpy(), cv)
    return shots.assign(shot_value=sv, best_alternative=best, edge=sv - best)


CONTEXT = {"360": True, "distance only": False}
MARGINS = {"any edge": 0, "clear edge": 0.02}
CORNERS = {"flat": False, "by team": True}
CHOICES_36 = {
    "option_pool": {name: LONG_POOLS[name] for name in OPTION_POOLS},
    "completion": COMPLETION_MODELS,
    "receiver_context": CONTEXT,
    "margin": MARGINS,
}
CHOICES_96 = {
    "option_pool": LONG_POOLS,
    "completion": {"distance": completion_distance, "pressure": completion_pressure,
                   "tracking": completion_tracking},
    "receiver_context": CONTEXT,
    "margin": MARGINS,
    "corners": CORNERS,
}


def original(shots):
    """The 36 from analysis/02-multiverse.R, off the long table."""
    with_context = fit_shot_value(shots, context=True)
    no_context = fit_shot_value(shots, context=False)
    t0 = time.perf_counter()
    opts = long_options(shots)

    def evaluate(pick):
        model = with_context if pick["receiver_context"] else no_context
        sc = score_long(shots, opts, model, pick["option_pool"], pick["completion"],
                        use_context=pick["receiver_context"])
        return {"shoot_was_right": 100 * np.mean(sc["edge"] > pick["margin"]),
                "mean_edge": sc["edge"].mean(),
                "mean_best_alternative": sc["best_alternative"].mean()}

    mv = multiverse(CHOICES_36, evaluate, verbose=False)
    timings["the 36"] = time.perf_counter() - t0
    return mv


def after_the_fixes(shots_all):
    """The 96 from analysis/05-fixes.R, off the long table."""
    shots = shots_all[shots_all["shot_type"] != "Free Kick"].reset_index(drop=True)
    shots = with_team_corners(shots, verbose=False)
    m_ctx = fit_shot_value(shots, context=True, keeper=True, space=True)
    m_noctx = fit_shot_value(shots, context=False, keeper=True, space=True)
    t0 = time.perf_counter()
    opts = long_options(shots)

    def evaluate(pick):
        model = m_ctx if pick["receiver_context"] else m_noctx
        sc = score_long(shots, opts, model, pick["option_pool"], pick["completion"],
                        use_context=pick["receiver_context"], offside_rule=True,
                        aftermath=AFTERMATH, team_corners=pick["corners"])
        return {"shoot_was_right": 100 * np.mean(sc["edge"] > pick["margin"]),
                "mean_edge": sc["edge"].mean()}

    mv = multiverse(CHOICES_96, evaluate, verbose=False)
    timings["the 96"] = time.perf_counter() - t0
    return mv


def largest_gap(mv, name):
    """How far these results sit from the ones run_multiverse.py wrote."""
    slow = pd.read_csv(REPORTS / name, float_precision="round_trip")
    decisions = [d for d in CHOICES_96 if d in slow]
    for d in decisions:
        if mv[d].tolist() != slow[d].astype(str).tolist():
            raise AssertionError(f"{name}: specifications in a different order at {d}")
    results = [c for c in slow.columns if c not in decisions]
    return np.max(np.abs(mv[results].to_numpy() - slow[results].to_numpy()))


def main():
    shots = pd.read_pickle(CACHE)
    mv36 = original(shots)
    mv96 = after_the_fixes(shots)

    print("share of shots where shooting was right, and the time to get there")
    for label, key, mv in [("the original 36:", "the 36", mv36),
                           ("the 96 after the fixes:", "the 96", mv96)]:
        swr = mv["shoot_was_right"]
        print(f"  {label:<24}{swr.min():.1f}% to {swr.max():.1f}%, {timings[key]:.2f} s")
    print("  (both include building the long table)")

    # A faster answer is only worth having if it is the same answer. The shot
    # by shot check is in tests/test_fast.py; this one is the headline.
    if (REPORTS / "specification-curve-py.csv").exists():
        gap = max(largest_gap(mv36, "specification-curve-py.csv"),
                  largest_gap(mv96, "specification-curve-v2-py.csv"))
        if gap > 1e-9:
            raise AssertionError(f"results differ from run_multiverse.py's by up to {gap:.3g}")
        print(f"\nlargest difference from the results run_multiverse.py wrote: {gap:.2g}")


if __name__ == "__main__":
    main()
