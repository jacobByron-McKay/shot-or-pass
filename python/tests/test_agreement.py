"""The Python port against the R original, on the same shots.

Needs the R side exported first, from the repository root:

    Rscript python/tests/export_r_reference.R

Geometry is deterministic, so features are held to 1e-9. Model coefficients
and per-shot values are held to 1e-6. The headline percentages are shares of
the same shots, so they should agree exactly; 0.1 points is the precision they
are reported at.
"""
import numpy as np
import pandas as pd
import pytest

import run_multiverse
from shotorpass.features import OPTION_COLUMNS
from shotorpass.multiverse import bootstrap_spread
from shotorpass.statsbomb import ROOT
from shotorpass.value import (AFTERMATH, completion_certain, completion_distance,
                              completion_pressure, completion_tracking, fit_shot_value,
                              pool_ahead, pool_clearly_ahead, pool_in_box, pool_with_cutbacks,
                              score_shots)

FEATURE_TOL = 1e-9
MODEL_TOL = 1e-6
HEADLINE_TOL = 0.1
BOOTSTRAP_TOL = 0.5

# name: (all shots or free kicks dropped, model, pool, completion, receiver
# context, offside rule and aftermath, team corners), the same nine
# export_r_reference.R scores
SPECS = {
    "v1_ahead_pressure_360":
        ("all", "v1_context", pool_ahead, completion_pressure, True, False, False),
    "v1_clearly_ahead_certain_360":
        ("all", "v1_context", pool_clearly_ahead, completion_certain, True, False, False),
    "v1_in_box_distance_distance_only":
        ("all", "v1_no_context", pool_in_box, completion_distance, False, False, False),
    "v2_with_cutbacks_tracking_360":
        ("no_fk", "v2_context", pool_with_cutbacks, completion_tracking, True, True, False),
    "v2_ahead_distance_distance_only":
        ("no_fk", "v2_no_context", pool_ahead, completion_distance, False, True, False),
    "v2_space_with_cutbacks_tracking_360_flat":
        ("no_fk", "v2_space_context", pool_with_cutbacks, completion_tracking, True, True, False),
    "v2_space_with_cutbacks_tracking_360_by_team":
        ("no_fk", "v2_space_context", pool_with_cutbacks, completion_tracking, True, True, True),
    "v2_space_clearly_ahead_distance_360_by_team":
        ("no_fk", "v2_space_context", pool_clearly_ahead, completion_distance, True, True, True),
    "v2_space_in_box_pressure_distance_only_flat":
        ("no_fk", "v2_space_no_context", pool_in_box, completion_pressure, False, True, False),
}
MODELS = ["v1_context", "v1_no_context", "v1_no_free_kicks", "v2_context", "v2_no_context",
          "v2_space_context", "v2_space_no_context"]
DECISIONS = ["option_pool", "completion", "receiver_context", "margin", "corners"]


def assert_close(py, r, tol, label):
    py, r = np.asarray(py, dtype=float), np.asarray(r, dtype=float)
    assert py.shape == r.shape, f"{label}: {py.shape} rows against {r.shape}"
    assert np.array_equal(np.isnan(py), np.isnan(r)), f"{label}: missing in different places"
    diff = np.nanmax(np.abs(py - r)) if py.size else 0.0
    assert diff <= tol, f"{label}: largest difference {diff:.3g}"


def assert_same(py, r, label):
    assert pd.Series(py).fillna("NA").tolist() == pd.Series(r).fillna("NA").tolist(), label


def long_table(shots, col):
    """The list column flattened the way the R export flattens it."""
    parts = [o.assign(shot_id=sid, option=np.arange(1, len(o) + 1))
             for sid, o in zip(shots["shot_id"], shots[col]) if len(o)]
    return pd.concat(parts, ignore_index=True)


def r_report(name):
    return pd.read_csv(ROOT / "reports" / name, float_precision="round_trip",
                       dtype={"receiver_context": str})


@pytest.fixture(scope="module")
def r_shots(r_ref):
    return r_ref("shots.csv")


@pytest.fixture(scope="module")
def cornered(shots):
    return run_multiverse.with_team_corners(shots, verbose=False)


@pytest.fixture(scope="module")
def models(shots_all, shots):
    return {
        "v1_context": fit_shot_value(shots_all, context=True),
        "v1_no_context": fit_shot_value(shots_all, context=False),
        "v1_no_free_kicks": fit_shot_value(shots, context=True),
        "v2_context": fit_shot_value(shots, context=True, keeper=True),
        "v2_no_context": fit_shot_value(shots, context=False, keeper=True),
        "v2_space_context": fit_shot_value(shots, context=True, keeper=True, space=True),
        "v2_space_no_context": fit_shot_value(shots, context=False, keeper=True, space=True),
    }


@pytest.fixture(scope="module")
def scored(shots_all, cornered, models):
    cache = {}

    def get(spec):
        if spec not in cache:
            which, model, pool, completion, context, fixed, corners = SPECS[spec]
            cache[spec] = score_shots(shots_all if which == "all" else cornered, models[model],
                                      pool, completion, use_context=context,
                                      offside_rule=fixed, aftermath=AFTERMATH if fixed else None,
                                      team_corners=corners)
        return cache[spec]
    return get


def test_the_same_shots_in_the_same_order(shots_all, r_shots):
    assert shots_all["shot_id"].tolist() == r_shots["shot_id"].tolist()


@pytest.mark.parametrize("column", [
    "match_id", "shot_id", "team", "player", "minute", "x", "y", "distance", "angle",
    "defenders_in_cone", "nearest_defender", "players_seen", "forward_visible", "body_part",
    "play_pattern", "statsbomb_xg", "goal", "shot_type", "first_time", "keeper_x", "keeper_y",
    "open_goal",
])
def test_shot_features_match(shots_all, r_shots, column):
    py, r = shots_all[column], r_shots[column]
    if pd.api.types.is_bool_dtype(r) or not pd.api.types.is_numeric_dtype(r):
        assert_same(py, r, column)
    else:
        assert_close(py, r, FEATURE_TOL, column)


@pytest.mark.parametrize("col", ["options", "behind"])
def test_option_lists_match(shots_all, r_ref, col):
    r = r_ref(f"{col}.csv")
    py = long_table(shots_all, col)[r.columns]
    for c in ["shot_id", "option", "offside"]:
        assert_same(py[c], r[c], f"{col}.{c}")
    for c in OPTION_COLUMNS:
        if c != "offside":
            assert_close(py[c], r[c], FEATURE_TOL, f"{col}.{c}")


def test_every_shot_gets_the_corner_value_r_gave_it(cornered, r_ref):
    r = r_ref("corner_values.csv")
    assert cornered["shot_id"].tolist() == r["shot_id"].tolist()
    assert_close(cornered["corner_value"], r["corner_value"], FEATURE_TOL, "corner_value")


@pytest.mark.parametrize("name", MODELS)
def test_shot_models_match(models, r_ref, name):
    fit = models[name]
    r = r_ref("coefficients.csv").query("model == @name")
    assert fit.params.index.tolist() == r["term"].replace("(Intercept)", "Intercept").tolist()
    assert_close(fit.params, r["estimate"], MODEL_TOL, f"{name} coefficients")
    assert_close(fit.bse, r["std_error"], MODEL_TOL, f"{name} standard errors")
    assert_close(fit.deviance, r["deviance"].iloc[0], MODEL_TOL, f"{name} deviance")


@pytest.mark.parametrize("spec", SPECS)
def test_per_shot_values_match(scored, r_ref, spec):
    py = scored(spec)
    r = r_ref("scores.csv").query("spec == @spec")
    assert py["shot_id"].tolist() == r["shot_id"].tolist()
    for c in ["shot_value", "best_alternative", "edge"]:
        assert_close(py[c], r[c], MODEL_TOL, f"{spec} {c}")


@pytest.mark.parametrize("spec", ["v1_ahead_pressure_360",
                                  "v2_space_with_cutbacks_tracking_360_flat"])
def test_bootstrap_widths_are_close(scored, r_ref, spec):
    # The bootstrap cannot match draw for draw. R's Mersenne Twister and numpy's
    # PCG64 give different resamples whatever the seed, so this compares only
    # the width of the interval, and the tolerance is the Monte Carlo noise of a
    # 2,000-draw bootstrap, not numerical error.
    b = bootstrap_spread(scored(spec), run_multiverse.shoot_was_right, n=2000, rng=2023)
    r = r_ref("bootstrap.csv").set_index("spec").loc[spec]
    assert abs(b["width"] - r["width"]) <= BOOTSTRAP_TOL


@pytest.fixture(scope="module")
def original_py(shots_all):
    return run_multiverse.original(shots_all)


@pytest.fixture(scope="module")
def fixes_py(shots_all):
    return run_multiverse.fixes(shots_all)


def assert_curve_matches(py, r, results):
    assert list(py.columns) == list(r.columns)
    for c in DECISIONS:
        if c in r:
            assert_same(py[c], r[c], c)
    assert_close(py["shoot_was_right"], r["shoot_was_right"], HEADLINE_TOL, "shoot_was_right")
    for c in results:
        assert_close(py[c], r[c], MODEL_TOL, c)


@pytest.mark.slow
def test_the_original_36_specifications_match(original_py):
    assert_curve_matches(original_py, r_report("specification-curve.csv"),
                         ["mean_edge", "mean_best_alternative"])


@pytest.mark.slow
def test_the_96_specifications_after_the_fixes_match(fixes_py):
    assert_curve_matches(fixes_py[1], r_report("specification-curve-v2.csv"), ["mean_edge"])


@pytest.mark.slow
def test_the_fix_by_fix_waterfall_matches(fixes_py):
    py, r = fixes_py[0], r_report("fix-waterfall.csv")
    assert_same(py["step"], r["step"], "step")
    assert_close(py["shoot_was_right"], r["shoot_was_right"], HEADLINE_TOL, "shoot_was_right")
    assert_close(py["change"], r["change"], HEADLINE_TOL, "change")
