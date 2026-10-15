# The Python port

The same analysis as `../R`, rewritten in Python and checked against the R
original shot by shot. The module and function names follow the R files one for
one: `geometry`, `statsbomb`, `features`, `value` and `multiverse`.

## Running it

Needs pandas, numpy, scipy, statsmodels (with patsy) and pytest, and the raw
StatsBomb files in `data-raw/`, which `build_shots.py` fetches if they are not
there. From this folder:

```
python build_shots.py       # the shot table, cached to ../cache/shots_py.pkl
python run_multiverse.py    # the 36, the fix-by-fix waterfall, the 96
```

`run_multiverse.py` writes `reports/specification-curve-py.csv`,
`reports/specification-curve-v2-py.csv` and `reports/fix-waterfall-py.csv` next
to the R versions, and prints how long each part took. `--rebuild` makes it build
the shot table from the raw JSON first and time that too.

The shot table keeps the R layout: one row per shot, with each shot's forward
options and behind options held as small data frames in object columns. pandas
allows that but nothing downstream expects it, so the cache is a pickle rather
than parquet.

## Tests

```
Rscript python/tests/export_r_reference.R   # once, from the repository root
cd python
pytest -m "not slow"    # about half a minute
pytest                  # adds both multiverses in full, about 10 minutes
```

The unit tests follow `tests/testthat` for geometry, value and multiverse.
`R/report.R` is not ported, so neither is its test file.

`test_agreement.py` compares the port against what the R code computes. The R
side comes from `tests/export_r_reference.R`, which writes the R shot table to
`cache/r-reference/` with the option lists flattened to long tables, plus the
model coefficients and per-shot scores under five fixed specifications that
between them use every option pool, every completion model, both receiver
contexts and both shot models. Doubles are written at 17 significant digits so
the export is exact.

| What | Held to | Largest difference found |
| --- | --- | --- |
| Shot ids, and their order | identical | identical |
| Every shot feature, forward option and behind option | 1e-9 | 2.2e-16 |
| GLM coefficients and standard errors (5 models) | 1e-6 | 2.0e-14, same IRLS iteration count |
| Shot value, best alternative and edge, per shot (5 specifications) | 1e-6 | 3.8e-15 |
| Share of shots where shooting was right, all 36 and all 96 | 0.1 points | 5.0e-14 |
| The fix-by-fix waterfall | 0.1 points | identical |
| Bootstrap interval width | 0.5 points | see below |

All 132 headline shares agree to 5.0e-14, which is the arithmetic of taking a
mean, so every shot gets the same verdict in both languages under every
specification.

The bootstrap is the one comparison that is not exact, and cannot be. R's
Mersenne Twister and numpy's PCG64 draw different resamples whatever the seed,
so the test only checks that the widths of the two intervals are close. Across
five numpy seeds the width on the original central specification ran from 4.66
to 4.98 points, against 4.79 from R. The R scripts and `run_multiverse.py` all
seed the bootstrap with 2023, so each prints the same interval every run, just
not the same interval as the other language: 4.79 points wide in R against 4.92
in Python on the original central specification, and 4.85 against 5.05 after
the fixes.

## Timings

Three runs of each, R and Python alternated, pinned to the same 6 performance
cores of an Intel i7-13700H with Windows' power throttling off, on mains power:
Windows 11, R 4.6.1, Python 3.14.4 with pandas 3.0.6, numpy 2.5.1 and
statsmodels 0.15.0. The figures are the medians, in seconds. Throttling matters
more than you would think: left on, as it is for a console process running in
the background, everything took 20 to 40% longer.

| | R | Python |
| --- | --- | --- |
| Build the shot table from the raw JSON | 96.0 | 9.9 |
| The original 36 specifications | 15.3 | 110.8 |
| The fix-by-fix waterfall | 6.3 | 46.1 |
| The 96 specifications after the fixes | 70.3 | 523.4 |
| One bootstrap, 2,000 resamples | 1.0 | 0.8 |

To reproduce: `Rscript python/timing.R` from the repository root for the R
column, and `python run_multiverse.py --rebuild` here for the Python one.

The two gaps run in opposite directions, and for unrelated reasons.

**The build.** R spends almost all of it parsing JSON. On eight matches,
`jsonlite::fromJSON(simplifyDataFrame = FALSE)` took 19.1 of the 20.0 seconds;
Python's `json` module took 0.9 of 1.9. The geometry itself costs about a
second per 166 shots in both.

**The multiverse.** Both versions score shot by shot, calling the model's
`predict()` once for the receivers of every shot that has any. That comes to
about 100,000 calls over a full run. In statsmodels each call sends the new data
back through patsy to rebuild the design matrix from the formula. Profiling a
single specification put four fifths of its time inside that machinery, when the
arithmetic it wraps is a dot product of four to six terms. R's `predict.glm`
rebuilds a model frame too, but more cheaply.

## The vectorised versions

`analysis/06-multiverse-fast.R` and `run_multiverse_fast.py` run the same 36 and
96 without the loop, alongside the shot-by-shot versions rather than in place of
them. Every option for every shot goes into one long table, what each row is
worth comes straight from the model's coefficients, and the best option for each
shot is a grouped maximum: `tapply()` in R, `np.maximum.at()` in Python.

```
Rscript analysis/06-multiverse-fast.R   # from the repository root, after 02 and 05
python run_multiverse_fast.py           # here, after run_multiverse.py
```

The answers are the same, not nearly the same. In R every shot's edge comes out
identical to the last bit. In Python numpy sums the dot product in its own
order, so an edge can move in the last few bits, never by more than 3.3e-16,
and no edge sits within 1e-6 of a margin. Every headline share agrees to 1e-9
and every shot gets the same verdict under all 132 specifications. The R script
checks all of that before it finishes; for Python the check is
`tests/test_fast.py`, whose slow half scores every combination both ways.

| | R, shot by shot | R, vectorised | Python, shot by shot | Python, vectorised |
| --- | --- | --- | --- | --- |
| The original 36 | 15.3 s | 0.22 s | 110.8 s | 0.19 s |
| The 96 after the fixes | 70.3 s | 0.35 s | 523.4 s | 0.29 s |

The same round of runs as the table above. The vectorised times include
building the long table, about 0.1 s of each.

On the 96, rewriting the loop was worth a factor of about 200 in R and 1,800 in
Python, while picking the faster language for the same loop was worth 7: how
you write it matters more than which language you write it in.

## Where the two differ

- **Summation.** R's `sum()` accumulates in extended precision. With plain
  double summation `polygon_area()` drifted from R in the last bit on 776
  shots, so the port uses `math.fsum` there and matches exactly. Nowhere else
  did it matter.
- **Missing values.** NaN for NA throughout. `open_goal_share()` relies on NaN
  comparing false to keep a missing keeper missing, where R has NA propagate.
- **List columns.** The R shot table holds each shot's options as a data frame
  inside a list column. The port keeps that shape in object columns, which is
  why the cache is a pickle and not parquet.
- **Model terms.** statsmodels calls the intercept `Intercept`, R calls it
  `(Intercept)`. Nothing else about the fits differs.
- **Ordering the specifications.** R sorts the pasted names in the locale's
  collation and Python by code point. For these names the two orders agree,
  and the test checks that they do.
- **Rounding.** The waterfall uses Python's `round()`, not `np.round()`.
  `round()` rounds the binary value actually stored, as R's `round()` does;
  `np.round()` scales first and can go the other way on a value like 0.15.
- **Reading R's CSVs.** pandas' default float parser can land one bit off a
  17-digit value, so the tests read the R export with
  `float_precision="round_trip"`.
