"""The vectorised multiverse against the shot-by-shot one.

Two things have to hold: every headline share within 1e-9, and every shot
given the same verdict. The quick tests check the 36 and the 96 against what
run_multiverse.py and the R scripts wrote, and the nine fixed specifications
shot by shot against R. The slow ones score every combination both ways in
Python, which takes score_shots() about ten minutes.
"""
from itertools import product

import numpy as np
import pandas as pd
import pytest

import run_multiverse_fast as fast
from run_multiverse import with_team_corners
from shotorpass.statsbomb import ROOT
from shotorpass.value import AFTERMATH, OPTION_POOLS, fit_shot_value, pool_with_cutbacks, score_shots

HEADLINE_TOL = 1e-9
EDGE_TOL = 1e-9
SHOT_BY_SHOT = {**OPTION_POOLS, "with_cutbacks": pool_with_cutbacks}


def report(name):
    return pd.read_csv(ROOT / "reports" / name, float_precision="round_trip",
                       dtype={"receiver_context": str})


def assert_curve_matches(mv, slow, results):
    assert list(mv.columns) == list(slow.columns)
    for d in fast.CHOICES_96:
        if d in slow:
            assert mv[d].tolist() == slow[d].tolist(), d
    for c in results:
        assert np.max(np.abs(mv[c] - slow[c])) <= HEADLINE_TOL, c


def assert_same_verdicts(edge, slow_edge, label):
    for m in fast.MARGINS.values():
        differ = int(np.sum((np.asarray(edge) > m) != (np.asarray(slow_edge) > m)))
        assert differ == 0, f"{label}: {differ} shots judged differently at margin {m}"


@pytest.fixture(scope="module")
def runs(shots_all, shots):
    """Each multiverse's shots, long table and models, and the fixes it has on."""
    shots = with_team_corners(shots, verbose=False)
    return {
        "v1": {"shots": shots_all, "opts": fast.long_options(shots_all),
               "models": {True: fit_shot_value(shots_all, context=True),
                          False: fit_shot_value(shots_all, context=False)},
               "choices": fast.CHOICES_36, "fixes": {}},
        "v2": {"shots": shots, "opts": fast.long_options(shots),
               "models": {True: fit_shot_value(shots, context=True, keeper=True, space=True),
                          False: fit_shot_value(shots, context=False, keeper=True, space=True)},
               "choices": fast.CHOICES_96,
               "fixes": {"offside_rule": True, "aftermath": AFTERMATH}},
    }


def score_long(run, pool, completion, context, corners=False):
    return fast.score_long(run["shots"], run["opts"], run["models"][context],
                           fast.LONG_POOLS[pool], run["choices"]["completion"][completion],
                           use_context=context, team_corners=corners, **run["fixes"])


def test_the_long_table_holds_every_option_once(shots_all, runs):
    opts = runs["v1"]["opts"]
    ahead, behind = shots_all["options"].map(len), shots_all["behind"].map(len)
    assert (~opts["behind"]).sum() == ahead.sum()
    assert opts["behind"].sum() == behind.sum()
    per_shot = opts.groupby("shot").size().reindex(range(len(shots_all)), fill_value=0)
    assert per_shot.tolist() == (ahead + behind).tolist()


@pytest.fixture(scope="module")
def mv36(shots_all):
    return fast.original(shots_all)


@pytest.fixture(scope="module")
def mv96(shots_all):
    return fast.after_the_fixes(shots_all)


@pytest.mark.parametrize("name", ["specification-curve-py.csv", "specification-curve.csv"])
def test_the_36_match_the_shot_by_shot_36(mv36, name):
    assert_curve_matches(mv36, report(name),
                         ["shoot_was_right", "mean_edge", "mean_best_alternative"])


@pytest.mark.parametrize("name", ["specification-curve-v2-py.csv", "specification-curve-v2.csv"])
def test_the_96_match_the_shot_by_shot_96(mv96, name):
    assert_curve_matches(mv96, report(name), ["shoot_was_right", "mean_edge"])


# The specifications export_r_reference.R scores shot by shot that the long
# table can reproduce, as (multiverse, option pool, completion model, receiver
# context, team corners). The two v2 ones without space are left out: the
# multiverse after the fixes always has space on.
R_SPECS = {
    "v1_ahead_pressure_360": ("v1", "ahead", "pressure", True, False),
    "v1_clearly_ahead_certain_360": ("v1", "clearly_ahead", "certain", True, False),
    "v1_in_box_distance_distance_only": ("v1", "in_box", "distance", False, False),
    "v2_space_with_cutbacks_tracking_360_flat": ("v2", "with_cutbacks", "tracking", True, False),
    "v2_space_with_cutbacks_tracking_360_by_team": ("v2", "with_cutbacks", "tracking", True, True),
    "v2_space_clearly_ahead_distance_360_by_team": ("v2", "clearly_ahead", "distance", True, True),
    "v2_space_in_box_pressure_distance_only_flat": ("v2", "in_box", "pressure", False, False),
}


@pytest.mark.parametrize("spec", R_SPECS)
def test_every_shot_gets_the_verdict_r_gave_it(runs, r_ref, spec):
    which, pool, completion, context, corners = R_SPECS[spec]
    sc = score_long(runs[which], pool, completion, context, corners)
    r = r_ref("scores.csv").query("spec == @spec")
    assert sc["shot_id"].tolist() == r["shot_id"].tolist()
    assert np.max(np.abs(sc["edge"].to_numpy() - r["edge"].to_numpy())) <= EDGE_TOL
    assert_same_verdicts(sc["edge"], r["edge"], spec)


# Every combination of pool, completion model, receiver context and corners in
# both multiverses. The margin does not change the scoring, so each is judged
# at both.
SCORINGS = [
    pytest.param(which, pool, completion, context, corners,
                 id="-".join([which, pool, completion, name, corner_name]).replace(" ", "_"))
    for which, choices in [("v1", fast.CHOICES_36), ("v2", fast.CHOICES_96)]
    for pool, completion, (name, context), (corner_name, corners) in product(
        choices["option_pool"], choices["completion"], choices["receiver_context"].items(),
        choices.get("corners", {"flat": False}).items())
]


@pytest.mark.slow
@pytest.mark.parametrize("which, pool, completion, context, corners", SCORINGS)
def test_every_shot_gets_the_same_verdict_as_score_shots(runs, which, pool, completion, context,
                                                         corners):
    run = runs[which]
    slow = score_shots(run["shots"], run["models"][context], SHOT_BY_SHOT[pool],
                       run["choices"]["completion"][completion], use_context=context,
                       team_corners=corners, **run["fixes"])
    quick = score_long(run, pool, completion, context, corners)
    label = f"{which} {pool} {completion} {context} {corners}"
    assert np.max(np.abs(quick["edge"] - slow["edge"])) <= EDGE_TOL, label
    assert_same_verdicts(quick["edge"], slow["edge"], label)
    for m in fast.MARGINS.values():
        share, slow_share = 100 * np.mean(quick["edge"] > m), 100 * np.mean(slow["edge"] > m)
        assert abs(share - slow_share) <= HEADLINE_TOL, label
