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

Needs R and `jsonlite`. The last script also needs `specr`.

```r
source("analysis/01-build-shots.R")   # fetches ~500 MB on a cold start
source("analysis/02-multiverse.R")
source("analysis/03-findings.R")
source("analysis/04-visibility-curve.R")
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
| `analysis/` | The four scripts, in order |
| `reports/findings.md` | Generated, not hand-written |

## The gate on the write-up

`reports/findings.md` is produced by code, and the code will not write it if the
prose contains a number the analysis did not compute. Values that are not
results, like the year or the number of matches, have to be declared explicitly
rather than waved through, so that adding one is a deliberate act.

It sounds fussy. It exists because a wrong figure in a published summary is
much more expensive than a missing one, and checking by eye works right up until
the day it does not.

## The camera hypothesis, and how it died

The freeze frames only cover what was on screen. The area ahead of a shooter was
in frame a median of 69.6% of the time, so roughly 30% of the space she might
have played into is missing from the record entirely.

That should bias the verdict. Less of the pitch visible means fewer options
recorded, means the best alternative is understated, means the shot looks more
justified than it was. Forward visibility does significantly predict how many
options get recorded, at p = 0.0034, so the censoring is real.

It does not reach the verdict. One regression put it at p = 0.218, which on its
own is not worth much, so this runs the question across 576 specifications with
`specr`: two outcomes, every subset of the geometry controls, and subsets by
shot distance, open play against set piece, and half.

![Specification curve for the visibility hypothesis](reports/visibility-specification-curve.png)

The median coefficient is 0.009. Estimates run from -1.7 to 1.75, near enough
symmetric about zero. Only 10.1% of specifications are significant at 0.05,
barely above what chance would give you, and 46.9% point the way the hypothesis
predicted, which is a coin flip. Just 3.0% are both significant and in the
predicted direction.

The hypothesis is not merely unsupported. It is unsupported robustly, which is a
stronger and more useful statement than a single p value ever is.

Two multiverses, doing different jobs. `specr` handles the model specification
side, which is what it was built for. `R/multiverse.R` handles the choices made
while constructing the numbers, which sit upstream of any model and which specr
does not cover. Harder (2020) makes the case for treating those as part of the
multiverse too.


## Where the method comes from

Running an analysis under every defensible version of its choices is not a new
idea. It is multiverse analysis (Steegen, Tuerlinckx, Gelman and Vanpaemel,
2016) and specification curve analysis (Simonsohn, Simmons and Nelson), both
well established in psychology and economics.

The most cited demonstration of the problem used football data. Silberzahn and
colleagues gave 29 analyst teams one dataset and asked whether referees give
more red cards to dark-skinned players. The teams reached materially different
answers from the same rows. "Many Analysts, One Data Set", 2018.

Football supplied the canonical example and football analytics then largely did
not adopt the response. That gap is what this repository is poking at.

Two CRAN packages already implement the general method well: `multiverse` and
`specr`. The harness in `R/multiverse.R` is a deliberately small thing, about
sixty lines, because the interesting object here is the sensitivity ranking
across a handful of domain choices rather than a general framework. If you want
to do this properly on your own work, start with `specr`.

## Prior work on the football question

Whether a player should have shot or passed is a well studied problem, not a new
one. Yeung and colleagues frame 1-vs-1 shot-taking game-theoretically (2024).
Caldeira and colleagues model finishing space value for shooting decisions
(2024). Decroos opens his thesis on valuing actions with exactly this question.

What is different here is not the question. It is running the answer 36 times.


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
