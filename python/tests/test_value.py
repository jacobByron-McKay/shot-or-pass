import numpy as np
import pandas as pd
import pytest
from scipy.special import expit

from shotorpass.geometry import GOAL_X, goal_angle, goal_distance
from shotorpass.value import (AFTERMATH, COMPLETION_MODELS, SPACE_CAP, best_alternative,
                              closing_in, completion_certain, completion_distance,
                              completion_pressure, completion_tracking, fit_shot_value,
                              pool_ahead, pool_in_box, pool_with_cutbacks, shot_value)


def fake_shots(n=400, seed=7):
    rng = np.random.default_rng(seed)
    d = pd.DataFrame({
        "distance": rng.uniform(5, 30, n),
        "y": rng.uniform(20, 60, n),
        "defenders_in_cone": rng.poisson(1.5, n),
    })
    d["angle"] = goal_angle(GOAL_X - d["distance"], d["y"])
    p = expit(-3 + 2 * d["angle"] - 0.4 * d["defenders_in_cone"])
    d["goal"] = rng.binomial(1, p)
    return d


@pytest.fixture(scope="module")
def model():
    return fit_shot_value(fake_shots())


def options(**cols):
    return pd.DataFrame(cols)


def test_the_shot_model_recovers_the_sign_of_a_known_effect(model):
    assert model.params["defenders_in_cone"] < 0
    assert model.params["angle"] > 0


def test_shot_value_falls_as_defenders_fill_the_cone(model):
    clear = shot_value(model, distance=12, angle=0.6, defenders_in_cone=0)
    crowded = shot_value(model, distance=12, angle=0.6, defenders_in_cone=4)
    assert clear > crowded


def test_completion_models_behave_the_way_their_names_claim():
    assert completion_certain(30, 1) == 1
    assert completion_distance(5, 1) > completion_distance(40, 1)
    assert completion_pressure(15, 12) > completion_pressure(15, 1)
    for f in COMPLETION_MODELS.values():
        v = f(np.array([3, 15, 45]), np.array([1, 5, 12]))
        assert np.all((v >= 0) & (v <= 1))


def test_the_best_alternative_is_zero_when_nobody_is_available(model):
    empty = options(x=[], y=[], distance=[], angle=[], defenders_in_cone=[],
                    nearest_defender=[], pass_length=[])
    assert best_alternative(empty, model, completion_certain) == 0


def test_the_best_alternative_picks_the_best_option_not_the_first(model):
    opts = options(
        x=[105, 112], y=[20, 40],
        distance=[goal_distance(105, 20), goal_distance(112, 40)],
        angle=[goal_angle(105, 20), goal_angle(112, 40)],
        defenders_in_cone=[3, 0], nearest_defender=[1, 8], pass_length=[5, 6],
    )
    best = best_alternative(opts, model, completion_certain)
    each = shot_value(model, opts.distance, opts.angle, opts.defenders_in_cone)
    assert best == pytest.approx(each.max())
    assert best > each.min()


def test_a_tighter_option_pool_can_only_remove_options_never_add_value(model):
    opts = options(x=[95, 110], y=[40, 40], distance=[25, 10], angle=[0.3, 0.8],
                   defenders_in_cone=[0, 0], nearest_defender=[9, 9], pass_length=[3, 20])
    wide = best_alternative(pool_ahead(opts), model, completion_certain)
    tight = best_alternative(pool_in_box(opts), model, completion_certain)
    assert tight <= wide


def test_the_measured_completion_model_rewards_space_and_punishes_a_blocked_lane():
    assert completion_tracking(10, 6, 0) > completion_tracking(10, 1, 0)
    assert completion_tracking(10, 6, 0) > completion_tracking(10, 6, 2)
    assert completion_tracking(5, 6, 0) > completion_tracking(25, 6, 0)
    v = completion_tracking(np.array([3, 15, 45]), np.array([1, 5, 12]), np.array([0, 1, 3]))
    assert np.all((v >= 0) & (v <= 1))


def test_the_cutback_pool_adds_the_teammates_behind_the_ball_and_nothing_else():
    ahead = options(x=[112], y=[40], distance=[8], angle=[0.9], defenders_in_cone=[1],
                    nearest_defender=[3], pass_length=[4], lane_blockers=[0],
                    offside=[False], open_goal=[0.8])
    behind = ahead.assign(x=105)
    shot = pd.Series({"x": 108, "behind": behind})
    assert len(pool_with_cutbacks(ahead, shot)) == 2
    assert len(pool_ahead(ahead, shot)) == 1


def test_the_offside_rule_can_only_remove_options_never_add_value(model):
    opts = options(x=[110, 116], y=[40, 40], distance=[10, 4], angle=[0.8, 1.6],
                   defenders_in_cone=[0, 0], nearest_defender=[5, 5], pass_length=[4, 8],
                   lane_blockers=[0, 0], offside=[False, True])
    with_rule = best_alternative(opts, model, completion_certain, offside_rule=True)
    without_rule = best_alternative(opts, model, completion_certain, offside_rule=False)
    assert with_rule <= without_rule


def test_a_miss_is_still_worth_something_more_so_close_to_goal():
    assert AFTERMATH["shot"](5) > AFTERMATH["shot"](28)
    assert np.all(AFTERMATH["shot"](np.array([1, 12, 40])) > 0)
    assert AFTERMATH["failed_pass"] < AFTERMATH["shot"](15)


def test_a_keeper_caught_off_the_line_makes_the_same_shot_worth_more():
    d = fake_shots(800)
    rng = np.random.default_rng(11)
    d["keeper_x"] = np.where(rng.uniform(size=len(d)) < 0.1, np.nan,
                             120 - rng.exponential(2.5, len(d)))
    off = np.where(d["keeper_x"].isna(), 2.4, 120 - d["keeper_x"])
    d["goal"] = rng.binomial(1, expit(-3 + 2 * d["angle"] - 0.4 * d["defenders_in_cone"] + 0.3 * off))
    m = fit_shot_value(d, keeper=True)
    on_line = shot_value(m, 12, 0.6, 0, keeper_x=119)
    caught = shot_value(m, 12, 0.6, 0, keeper_x=112)
    unseen = shot_value(m, 12, 0.6, 0, keeper_x=np.nan)
    assert caught > on_line
    assert np.isfinite(unseen).all()


def test_a_receiver_with_room_loses_some_of_it_by_the_time_the_ball_arrives():
    assert closing_in(9, 20) < 9
    assert closing_in(9, 20) > closing_in(4, 20)
    assert closing_in(9, 30) < closing_in(9, 5)
    assert closing_in(np.array([1, 50, 99]), 10).max() <= SPACE_CAP


def test_an_average_corner_reproduces_the_flat_aftermath_values_exactly():
    flat = [0.0455, 0.0235, 0.0226, 0.0101, 0.0034]
    assert AFTERMATH["shot"](np.array([4, 10, 15, 21.5, 30])) == pytest.approx(flat, abs=1e-4)
    assert AFTERMATH["shot"](12, 0.07) > AFTERMATH["shot"](12, 0.03)


def test_space_only_enters_the_value_when_the_model_was_fitted_with_it():
    d = fake_shots()
    d["nearest_defender"] = np.random.default_rng(13).uniform(0.5, 12, len(d))
    m0 = fit_shot_value(d)
    m1 = fit_shot_value(d, space=True)
    assert shot_value(m0, 12, 0.6, 0, space=1) == shot_value(m0, 12, 0.6, 0, space=9)
    assert "space" in m1.params.index
