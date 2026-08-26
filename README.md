# Should they have passed?

When a player shoots, could we tell from the positional data that passing was
the better option? And more to the point: how much does the answer depend on
choices the analyst made along the way and never wrote down?

Built on StatsBomb's open data for the 2023 Women's World Cup. All 64 matches,
1,566 shots with penalties excluded, and a freeze frame for every one of them
giving the positions of the players the broadcast camera could see.

## What came out of it

Deciding whether a shot was the right call takes four further decisions. Which
teammates count as a real option. How likely a pass is to arrive. Whether the
receiver is valued using her positional context or on distance alone. How much
better the alternative has to be before you call the shot wrong.

Run all 36 combinations and the share of shots where shooting beat the best
available alternative lands anywhere between 31.7% and 46.3%. Every one of those
specifications is defensible. None of them is wrong.

The ranking is the part I did not expect:

| Decision | Moves the answer by |
| --- | --- |
| Which teammates count as an option | 7.7 points |
| How large an edge counts as an edge | 4.5 points |
| Chance the pass arrives | 1.9 points |
| Whether the receiver gets positional context | 0.3 points |

The last one is the term with the significant coefficient behind it, the one
that would get a paragraph in a write-up. It barely touches the headline. The
first one is a single line of filtering that nobody would think to mention.

Holding a specification fixed and resampling the shots gives a 95% interval 4.9
points wide. The spread across specifications is 14.6, close to three times
larger. The error bar that gets published is the smaller of the two.

That is not a general law, and I have a counterexample in my own working: on a
simpler counting question over the same tournament the two came out about equal.
Which is the argument for running the specifications rather than reasoning about
them.

## The shot model

Distance to goal, the angle the goalmouth subtends, and how many defenders are
standing inside the triangle between the ball and the posts. That third term is
what the freeze frames buy, and it holds up: significant at p = 0.0013, and the
likelihood ratio test against the two-term model gives p = 0.00036.

It predicts a mean scoring rate equal to the observed 0.0837 and correlates 0.72
with the xG StatsBomb ship alongside the data, which is close enough for a
three-term model fitted on one tournament.

## Running it

Needs R and `jsonlite`. Nothing else.

```r
source("analysis/01-build-shots.R")   # fetches ~500 MB on a cold start
source("analysis/02-multiverse.R")
source("analysis/03-findings.R")
```

Tests:

```r
Rscript tests/testthat.R
```

## What is in here

| File | |
| --- | --- |
| `R/geometry.R` | Pitch geometry: goal angle, the shooting cone, clipping the camera's visible area |
| `R/statsbomb.R` | Reading the open data, and fetching it when it is missing |
| `R/features.R` | One row per shot, with the passing options visible at that instant |
| `R/value.R` | The shot model, three views of pass completion, three ways to decide what counts as an option |
| `R/multiverse.R` | Runs every combination of choices and reports which ones matter |
| `R/report.R` | Checks that every figure in the written findings is one the analysis produced |
| `analysis/` | The three scripts, in order |
| `reports/findings.md` | Generated, not hand-written |

## The gate on the write-up

`reports/findings.md` is produced by code, and the code will not write it if the
prose contains a number the analysis did not compute. Values that are not
results, like the year or the number of matches, have to be declared explicitly
rather than waved through, so that adding one is a deliberate act.

It sounds fussy. It exists because a wrong figure in a published summary is
much more expensive than a missing one, and checking by eye works right up until
the day it does not.

## Limitations

Freeze frames carry no player identities, only a flag for teammate or opponent.
So a shooter's decision can be attributed to her, but the teammate she should
have found stays anonymous.

The camera only shows part of the pitch. The area ahead of the shooter was in
frame a median of 69.6% of the time, so about 30% of the space she might have
played into is simply absent. Counting her options means counting the options a
broadcast director chose to frame. I tested whether that censoring bends the
verdict and it does not, which was not what I expected when I wrote the test.

Pass completion is modelled, not measured. The three versions here are stated
assumptions, which is the honest way round, but they are still assumptions.

One tournament, 1,566 shots. Wide enough for a spread, not wide enough for a law.

## Data

StatsBomb open data: https://github.com/statsbomb/open-data

Free for public use. If you publish anything based on it, credit StatsBomb as
the source. Nothing from it is committed here; the scripts fetch what they need.
