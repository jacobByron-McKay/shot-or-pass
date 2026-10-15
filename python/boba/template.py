"""The 96 specifications after the fixes, written as a boba template.

The same analysis as after_the_fixes() in run_multiverse_fast.py, laid out the
way boba (github.com/uwdata/boba) wants it: one script, with each decision
marked at the place it is made. boba compiles it into 96 plain scripts, one
per universe, runs each as its own process and merges what they write. Open
any compiled universe and it is the analysis under one set of choices, with
nothing left to look up.

Four of the five decisions are names dropped into the code, listed in the
config below. They are the names the reports use, looked up in the same
dictionaries run_multiverse_fast.py runs on, so summary.csv and boba-server
talk in the report's terms. Plain true and false would read better in the
code but break boba-server, which cannot match them to summary.csv.

The option pool changes the code itself, so each answer to it is a block of
its own and boba takes one per universe. The visualizer entry tells
boba-server (pip install boba-visualizer) which merged column to plot.

run_boba.py, next to this file, compiles, runs and merges it and checks the
result against reports/specification-curve-v2-py.csv.
"""
from pathlib import Path

import numpy as np
import pandas as pd

from run_multiverse import with_team_corners
from run_multiverse_fast import CACHE, CONTEXT, CORNERS, MARGINS, long_options, score_long
from shotorpass.value import (AFTERMATH, completion_distance, completion_pressure,
                              completion_tracking, fit_shot_value, pool_ahead,
                              pool_clearly_ahead, pool_in_box)

# --- (BOBA_CONFIG)
{
  "decisions": [
    {"var": "receiver_context", "options": ["360", "distance only"]},
    {"var": "completion", "options": ["distance", "pressure", "tracking"]},
    {"var": "corners", "options": ["flat", "by team"]},
    {"var": "margin", "options": ["any edge", "clear edge"]}
  ],
  "visualizer": {
    "files": [{"id": "results", "path": "merged.csv"}],
    "schema": {"point_estimate": {"file": "results", "field": "shoot_was_right"}}
  }
}
# --- (END)

shots = pd.read_pickle(CACHE)
shots = shots[shots["shot_type"] != "Free Kick"].reset_index(drop=True)
shots = with_team_corners(shots, verbose=False)
opts = long_options(shots)

# Whether a receiver's chance counts the bodies in their shooting cone. The
# same choice decides which shot model gets fitted, so it is made once here.
use_context = CONTEXT["{{receiver_context}}"]
model = fit_shot_value(shots, context=use_context, keeper=True, space=True)

# Which teammates count as a real alternative to shooting. The first three
# only look at players ahead of the ball.

# --- (option_pool) ahead
def pool(o):
    return pool_ahead(o[~o["behind"]])

# --- (option_pool) clearly_ahead
def pool(o):
    return pool_clearly_ahead(o[~o["behind"]])

# --- (option_pool) in_box
def pool(o):
    return pool_in_box(o[~o["behind"]])

# --- (option_pool) with_cutbacks
# everyone ahead, plus the lay-offs and cutbacks behind the ball
def pool(o):
    return o

# --- (score)
# Offside receivers are dropped and a miss or a failed pass keeps some value
# in every universe. The rules and the data settle those; they are not choices.
sc = score_long(shots, opts, model, pool, completion_{{completion}},
                use_context=use_context, offside_rule=True, aftermath=AFTERMATH,
                team_corners=CORNERS["{{corners}}"])

# One small file per universe for boba merge to stitch together. The choices
# are not repeated here because boba's summary.csv already records them.
result = pd.DataFrame({"shoot_was_right": [100 * np.mean(sc["edge"] > MARGINS["{{margin}}"])],
                       "mean_edge": [sc["edge"].mean()]})
Path("../results").mkdir(exist_ok=True)
result.to_csv("../results/result_{{_n}}.csv", index=False)
print(f"shooting was right on {result['shoot_was_right'].iat[0]:.1f}% of shots")
