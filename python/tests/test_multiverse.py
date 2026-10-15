import numpy as np
import pandas as pd

from shotorpass.multiverse import bootstrap_spread, multiverse, sensitivity, specifications


def test_every_combination_of_choices_is_generated_exactly_once():
    choices = {"a": {"one": 1, "two": 2}, "b": {"x": "x", "y": "y", "z": "z"}}
    spec = specifications(choices)
    assert len(spec) == 6
    assert len(spec.drop_duplicates()) == 6
    assert set(spec.columns) == {"a", "b"}


def test_the_harness_passes_the_selected_values_through_not_their_names():
    choices = {"f": {"double": lambda x: x * 2, "treble": lambda x: x * 3}}
    mv = multiverse(choices, lambda pick: {"out": pick["f"](10)}, verbose=False)
    assert set(mv["out"]) == {20, 30}


def test_sensitivity_ranks_the_decision_that_moves_the_outcome_most():
    mv = pd.DataFrame({
        "big": np.repeat(["lo", "hi"], 4),
        "small": np.tile(["lo", "hi"], 4),
        "value": [1, 1.1, 1, 1.1, 9, 9.1, 9, 9.1],
    })
    s = sensitivity(mv, "value", decisions=["big", "small"])
    assert s["decision"].iloc[0] == "big"
    assert s["spread"].iloc[0] > s["spread"].iloc[1]


def test_a_decision_that_changes_nothing_has_no_spread():
    mv = pd.DataFrame({"inert": ["a", "a", "b", "b"], "value": [5, 5, 5, 5]})
    s = sensitivity(mv, "value", decisions=["inert"])
    assert s["spread"].iloc[0] == 0


def test_the_bootstrap_interval_brackets_the_observed_statistic():
    x = np.random.default_rng(42).normal(10, 1, 500)
    b = bootstrap_spread(x, np.mean, n=500, rng=42)
    assert b["low"] < 10 < b["high"]
    assert b["width"] == b["high"] - b["low"]


def test_the_bootstrap_accepts_a_data_frame_and_resamples_its_rows():
    d = pd.DataFrame({"v": [0] * 50 + [1] * 50})
    b = bootstrap_spread(d, lambda x: x["v"].mean(), n=300, rng=1)
    assert b["low"] > 0.3 and b["high"] < 0.7
