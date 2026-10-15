"""Run an analysis under every defensible version of every choice in it.

The argument this repository is making is that you cannot tell by reasoning
which of your choices your conclusion depends on. You have to run them all
and look.
"""
from itertools import product

import numpy as np
import pandas as pd


def specifications(choices):
    """Every combination of the supplied choices.

    `choices` is a dict of dicts. Each outer key is a decision point in the
    analysis, each inner key is one defensible way of settling it.
    """
    grid = pd.DataFrame(list(product(*[list(c) for c in choices.values()])),
                        columns=list(choices))
    # sorted on the names pasted together, as in the R version. R sorts in the
    # locale's collation and Python by code point; for these names they agree
    order = grid.apply("".join, axis=1).sort_values(kind="stable").index
    return grid.loc[order].reset_index(drop=True)


def multiverse(choices, evaluate, verbose=True):
    """Run `evaluate` once per specification.

    `evaluate` receives a dict holding one selected value per decision point,
    and returns a dict of named results. The returned frame has one row per
    specification with the choices alongside the results, which is what a
    specification curve is drawn from.
    """
    grid = specifications(choices)
    out = []
    for i, spec in enumerate(grid.itertuples(index=False), 1):
        picked = {cp: choices[cp][name] for cp, name in zip(grid.columns, spec)}
        out.append(evaluate(picked))
        if verbose:
            print(f"\r{i}/{len(grid)} specifications", end="")
    if verbose:
        print()
    return pd.concat([grid, pd.DataFrame(out)], axis=1)


def sensitivity(mv, outcome, decisions=None):
    """How much each decision point moves a result, holding the others as they lie.

    The spread column is the gap between the best and worst outcome you would
    report depending purely on how that one decision went. A choice with a large
    spread has to be disclosed. A choice with a small one can be settled however
    you like and forgotten about.
    """
    if decisions is None:
        decisions = [c for c in mv.columns if c != outcome]
    rows = []
    for d in decisions:
        m = mv.groupby(d)[outcome].mean()
        rows.append({"decision": d, "levels": len(m), "low": m.min(), "high": m.max(),
                     "spread": m.max() - m.min()})
    res = pd.DataFrame(rows)
    return res.sort_values("spread", ascending=False, kind="stable").reset_index(drop=True)


def bootstrap_spread(x, statistic, n=1000, conf=0.95, rng=None):
    """Sampling spread for the same outcome, so the two can be compared honestly.

    Definitional spread that is small next to sampling noise is not worth
    reporting. Definitional spread that is larger is the one nobody mentions.
    """
    rng = np.random.default_rng(rng)
    is_frame = isinstance(x, pd.DataFrame)
    if not is_frame:
        x = np.asarray(x)
    n_obs = len(x)
    reps = []
    for _ in range(n):
        idx = rng.integers(0, n_obs, n_obs)
        reps.append(statistic(x.iloc[idx] if is_frame else x[idx]))
    low, high = np.quantile(reps, [(1 - conf) / 2, 1 - (1 - conf) / 2])
    return {"low": low, "high": high, "width": high - low}
