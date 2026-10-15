"""The original 36 specifications, then the fixes one at a time, then the 96
specifications after them. The Python counterpart of analysis/02-multiverse.R
and analysis/05-fixes.R.

    python run_multiverse.py            # uses cache/shots_py.pkl
    python run_multiverse.py --rebuild  # builds it from the raw JSON first

The team corner ratings come from cache/corner_ratings.csv, which
tests/export_r_reference.R writes from the .rds that analysis/05 reads.
"""
import sys
import time

import numpy as np
import pandas as pd
from scipy import stats

from shotorpass.features import build_shots
from shotorpass.multiverse import bootstrap_spread, multiverse, sensitivity, specifications
from shotorpass.statsbomb import ROOT, sb_matches
from shotorpass.value import (AFTERMATH, COMPLETION_MODELS, CORNER_XG, OPTION_POOLS,
                              completion_distance, completion_pressure, completion_tracking,
                              fit_shot_value, pool_ahead, pool_with_cutbacks, score_shots)

CACHE = ROOT / "cache" / "shots_py.pkl"
CORNER_RATINGS = ROOT / "cache" / "corner_ratings.csv"
REPORTS = ROOT / "reports"
# The bootstrap's seed, so the interval and the ratio built on it print the
# same every run. 2023 for the tournament year, as in the R scripts, though
# numpy and R draw different resamples from the same seed.
SEED = 2023
timings = {}


def timed(label, f, *args, **kwargs):
    t0 = time.perf_counter()
    out = f(*args, **kwargs)
    timings[label] = time.perf_counter() - t0
    return out


def shoot_was_right(d):
    return 100 * np.mean(d["edge"] > 0)


def print_range(mv):
    swr = mv["shoot_was_right"]
    print(f"  lowest specification:  {swr.min():.1f}%")
    print(f"  highest specification: {swr.max():.1f}%")
    print(f"  spread:                {swr.max() - swr.min():.1f} points")


def print_sensitivity(sens):
    print(sens.round({"low": 1, "high": 1, "spread": 1}).to_string(index=False))


def with_team_corners(shots, verbose=True):
    """Each shot's corner value: this team's corners against this opponent's,
    from earlier games weighted by how many of today's starters played in them.
    A shot without a rating gets the average corner."""
    if not CORNER_RATINGS.exists():
        raise FileNotFoundError("no cache/corner_ratings.csv: run "
                                "`Rscript python/tests/export_r_reference.R` from the "
                                "repository root first")
    cr = pd.read_csv(CORNER_RATINGS, float_precision="round_trip")
    rating = cr.set_index(["match_id", "team"])["matchup"]
    key = pd.MultiIndex.from_arrays([shots["match_id"], shots["team"]])
    rated = rating.reindex(key).to_numpy()
    if verbose:
        print(f"shots with a team corner rating: {100 * np.mean(~np.isnan(rated)):.1f}%")
    return shots.assign(corner_value=np.where(np.isnan(rated), CORNER_XG, rated))


def original(shots):
    """analysis/02-multiverse.R: which of the choices actually move the conclusion?"""
    with_context = fit_shot_value(shots, context=True)
    no_context = fit_shot_value(shots, context=False)

    print("\nshot value model")
    table = pd.DataFrame({"Estimate": with_context.params, "Std. Error": with_context.bse,
                          "z value": with_context.tvalues, "Pr(>|z|)": with_context.pvalues})
    print(table.round(4))
    lrt = stats.chi2.sf(no_context.deviance - with_context.deviance, df=1)
    print(f"\nAIC with defenders in cone: {with_context.aic:.1f}  without: {no_context.aic:.1f}")
    print(f"likelihood ratio test p: {lrt:.3g}")

    pred = with_context.predict(shots)
    print(f"observed goal rate: {shots['goal'].mean():.4f}  mean predicted: {pred.mean():.4f}"
          f"  correlation with StatsBomb xG: {np.corrcoef(pred, shots['statsbomb_xg'])[0, 1]:.3f}")

    print("\ncalibration by decile of predicted value")
    dec = pd.cut(pred, np.quantile(pred, np.linspace(0, 1, 11)), include_lowest=True, labels=False) + 1
    calib = pd.DataFrame({"pred": pred, "goal": shots["goal"], "decile": dec}).groupby("decile")
    print(pd.DataFrame({"n": calib.size(), "predicted": calib["pred"].mean().round(3),
                        "observed": calib["goal"].mean().round(3)}).to_string())

    # Four decision points. Each one is a question somebody has to answer to get
    # a number out, and each has more than one defensible answer.
    choices = {
        "option_pool": OPTION_POOLS,
        "completion": COMPLETION_MODELS,
        "receiver_context": {"360": True, "distance only": False},
        "margin": {"any edge": 0, "clear edge": 0.02},
    }
    print(f"\nrunning {len(specifications(choices))} specifications")

    def evaluate(pick):
        model = with_context if pick["receiver_context"] else no_context
        scored = score_shots(shots, model, pick["option_pool"], pick["completion"],
                             use_context=pick["receiver_context"])
        return {"shoot_was_right": 100 * np.mean(scored["edge"] > pick["margin"]),
                "mean_edge": scored["edge"].mean(),
                "mean_best_alternative": scored["best_alternative"].mean()}

    mv = timed("the 36", multiverse, choices, evaluate)
    print("\nshare of shots where shooting beat the best alternative")
    print_range(mv)
    print("\nwhich decision moves it, largest first")
    print_sensitivity(sensitivity(mv, "shoot_was_right", decisions=list(choices)))

    # How wide is the sampling interval on the same quantity?
    mid = score_shots(shots, with_context, pool_ahead, completion_pressure, use_context=True)
    boot = timed("bootstrap, original", bootstrap_spread, mid, shoot_was_right, n=2000,
                 rng=SEED)
    spread = mv["shoot_was_right"].max() - mv["shoot_was_right"].min()
    print(f"\nsampling: 95% interval on one fixed specification is "
          f"[{boot['low']:.1f}%, {boot['high']:.1f}%], width {boot['width']:.1f} points")
    print(f"definitional spread across all specifications: {spread:.1f} points")
    print(f"ratio definitional to sampling: {spread / boot['width']:.2f}")
    return mv


def fixes(shots_all):
    """analysis/05-fixes.R: what the error analysis changed, one fix at a time,
    then the multiverse again."""
    def central(shots, model, pool=pool_ahead, completion=completion_pressure,
                offside_rule=False, aftermath=None, team_corners=False):
        sc = score_shots(shots, model, pool, completion, use_context=True,
                         offside_rule=offside_rule, aftermath=aftermath,
                         team_corners=team_corners)
        return shoot_was_right(sc)

    shots = shots_all[shots_all["shot_type"] != "Free Kick"].reset_index(drop=True)
    shots = with_team_corners(shots)
    m_v1 = fit_shot_value(shots_all, context=True)
    m_v1_nofk = fit_shot_value(shots, context=True)
    m_keep = fit_shot_value(shots, context=True, keeper=True)
    m_space = fit_shot_value(shots, context=True, keeper=True, space=True)

    def waterfall():
        return [
            ("as submitted", central(shots_all, m_v1)),
            ("drop direct free kicks", central(shots, m_v1_nofk)),
            ("+ offside options removed", central(shots, m_v1_nofk, offside_rule=True)),
            ("+ keeper off the line", central(shots, m_keep, offside_rule=True)),
            ("+ what a miss or a bad pass still leads to",
             central(shots, m_keep, offside_rule=True, aftermath=AFTERMATH)),
            ("+ completion measured on tracking (lanes)",
             central(shots, m_keep, completion=completion_tracking, offside_rule=True,
                     aftermath=AFTERMATH)),
            ("+ cutbacks and lay-offs",
             central(shots, m_keep, pool=pool_with_cutbacks, completion=completion_tracking,
                     offside_rule=True, aftermath=AFTERMATH)),
            ("+ space, with defenders closing in",
             central(shots, m_space, pool=pool_with_cutbacks, completion=completion_tracking,
                     offside_rule=True, aftermath=AFTERMATH)),
            ("(branch) team corner ratings",
             central(shots, m_space, pool=pool_with_cutbacks, completion=completion_tracking,
                     offside_rule=True, aftermath=AFTERMATH, team_corners=True)),
        ]

    steps = timed("waterfall", waterfall)
    wf = pd.DataFrame(steps, columns=["step", "shoot_was_right"])
    # builtin round, not np.round: it rounds the exact binary value, as R does
    wf["shoot_was_right"] = [round(v, 1) for v in wf["shoot_was_right"]]
    wf["change"] = [np.nan] + [round(v, 1) for v in np.diff(wf["shoot_was_right"])]
    print("\none specification, fix by fix: share of shots where shooting was right")
    print(wf.to_string(index=False))

    # Offside, the keeper, the aftermath and space with defenders closing in are
    # settled by the rules or the data, so they are always on. Assuming every
    # pass arrives is no longer defensible (68% do), so that branch goes.
    # Cutbacks join the option pool, the measured completion model joins the
    # assumed ones, and a team's own corner record is tested against the flat
    # average.
    m_ctx = m_space
    m_noctx = fit_shot_value(shots, context=False, keeper=True, space=True)
    choices = {
        "option_pool": {**OPTION_POOLS, "with_cutbacks": pool_with_cutbacks},
        "completion": {"distance": completion_distance, "pressure": completion_pressure,
                       "tracking": completion_tracking},
        "receiver_context": {"360": True, "distance only": False},
        "margin": {"any edge": 0, "clear edge": 0.02},
        "corners": {"flat": False, "by team": True},
    }
    print(f"\nrunning {len(specifications(choices))} specifications")

    def evaluate(pick):
        model = m_ctx if pick["receiver_context"] else m_noctx
        sc = score_shots(shots, model, pick["option_pool"], pick["completion"],
                         use_context=pick["receiver_context"], offside_rule=True,
                         aftermath=AFTERMATH, team_corners=pick["corners"])
        return {"shoot_was_right": 100 * np.mean(sc["edge"] > pick["margin"]),
                "mean_edge": sc["edge"].mean()}

    mv = timed("the 96", multiverse, choices, evaluate)
    print("\nshare of shots where shooting beat the best alternative, after the fixes")
    print_range(mv)
    print_sensitivity(sensitivity(mv, "shoot_was_right", decisions=list(choices)))

    mid = score_shots(shots, m_ctx, pool_with_cutbacks, completion_tracking, use_context=True,
                      offside_rule=True, aftermath=AFTERMATH)
    boot = timed("bootstrap, after the fixes", bootstrap_spread, mid, shoot_was_right, n=2000,
                 rng=SEED)
    spread = mv["shoot_was_right"].max() - mv["shoot_was_right"].min()
    print(f"\nsampling: 95% interval on the fixed central specification "
          f"[{boot['low']:.1f}%, {boot['high']:.1f}%], width {boot['width']:.1f} points")
    print(f"ratio definitional to sampling: {spread / boot['width']:.2f}")
    return wf, mv


def main():
    if "--rebuild" in sys.argv or not CACHE.exists():
        ids = [m["match_id"] for m in sb_matches()]
        shots = timed("build", build_shots, ids)
        shots.to_pickle(CACHE)
    else:
        shots = pd.read_pickle(CACHE)
    print("shots:", len(shots))

    mv1 = original(shots)
    wf, mv2 = fixes(shots)

    REPORTS.mkdir(exist_ok=True)
    mv1.to_csv(REPORTS / "specification-curve-py.csv", index=False)
    mv2.to_csv(REPORTS / "specification-curve-v2-py.csv", index=False)
    wf.to_csv(REPORTS / "fix-waterfall-py.csv", index=False, na_rep="NA")
    print("\nwritten to reports/specification-curve-py.csv, reports/specification-curve-v2-py.csv"
          " and reports/fix-waterfall-py.csv")

    print("\nwall-clock time")
    if "build" not in timings:
        print("  build                         (cached table; --rebuild to time it)")
    for label, secs in timings.items():
        print(f"  {label:<30}{secs:6.1f} s")


if __name__ == "__main__":
    main()
