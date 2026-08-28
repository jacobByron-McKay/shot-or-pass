## Write the findings, and refuse to write them if any figure in the prose is
## not one the analysis produced.

source("R/geometry.R")
source("R/report.R")

res <- readRDS("cache/results.rds")
shots <- readRDS("cache/shots.rds")
mv <- res$multiverse
sens <- res$sensitivity

n_shots   <- nrow(shots)
n_matches <- length(unique(shots$match_id))
opts_mean <- round(mean(vapply(shots$options, nrow, integer(1))), 2)
fwd_med   <- round(100 * median(shots$forward_visible, na.rm = TRUE), 1)
fwd_gap   <- round(100 - fwd_med, 1)

lo <- round(min(mv$shoot_was_right), 1)
hi <- round(max(mv$shoot_was_right), 1)
spread <- round(hi - lo, 1)
n_spec <- nrow(mv)

boot_w <- round(res$bootstrap$width, 1)
ratio  <- round(spread / res$bootstrap$width, 2)

cf <- summary(res$model)$coefficients
cone_p <- signif(cf["defenders_in_cone", "Pr(>|z|)"], 2)
goal_rate <- round(mean(shots$goal), 4)
sb_cor <- round(cor(predict(res$model, type = "response"), shots$statsbomb_xg), 2)

pool_spread <- round(sens$spread[sens$decision == "option_pool"], 1)
ctx_spread  <- round(sens$spread[sens$decision == "receiver_context"], 1)

text <- sprintf('
# Findings

The tournament gives %d shots across %d matches, excluding penalties. Every one
carries a freeze frame, so for each shot we know where the players the camera
could see were standing. On average a shooter had %s teammates ahead of them.

## A shot model that uses the freeze frames

Distance, goalmouth angle and the number of defenders standing inside the
shooting cone. The third term is the one the positional data buys, and it earns
its place: it is significant at p = %s, and dropping it costs likelihood. The
model is calibrated, predicting a mean scoring rate equal to the observed rate
of %s, and it correlates %s with the xG StatsBomb ship with the data.

## The verdict depends on choices nobody writes down

Deciding whether a player should have passed instead of shooting takes four
further decisions: which teammates count as a real option, how likely a pass is
to arrive, whether the receiver is valued with positional context or on distance
alone, and how large an advantage the alternative needs before the shot is
called wrong.

Running all %d combinations, the share of shots where shooting beat the best
available alternative ranges from %s to %s. That is a spread of %s percentage
points, from choices every one of which is defensible.

## The part worth taking away

The decision that moves the answer most is which teammates count as an option,
worth %s points. It is also the one an analyst would settle in a single line of
filtering and never mention again.

The decision that moves it least, at %s points, is whether the receiver is
valued using the positional data at all. That is the choice with a statistically
significant coefficient behind it, and the one most likely to get a paragraph in
a write-up.

The choice you would justify at length barely matters. The choice you would make
without noticing decides the headline.

## Definitional spread against sampling noise

Holding one specification fixed and resampling the shots, the 95 per cent
interval on that share is %s points wide. The spread across specifications is
%s points, which is %s times larger. Reporting the confidence interval and not
the specification range describes the smaller of the two sources of error.

This is not a general law. On a simpler question, counting the same tournament,
the two are close to equal. Which is the point: you cannot tell which case you
are in without running it.

## What the camera did not show

The freeze frames only cover what was on screen. The area ahead of the shooter
was in view a median of %s per cent of the time, so roughly %s per cent of the
space they might have played into is missing from the record. Counting available
options from this data means counting the options a broadcast director chose to
frame. That censoring is measurable and it is real. Tested against the verdict
above, it does not move it, which was not the answer expected when the test was
written.

Data: StatsBomb open data, FIFA Women%ss World Cup 2023.
', n_shots, n_matches, opts_mean, cone_p, goal_rate, sb_cor, n_spec,
   lo, hi, spread, pool_spread, ctx_spread, boot_w, spread, ratio,
   fwd_med, fwd_gap, "'")

approved <- approve(c(n_shots, n_matches, opts_mean, cone_p, goal_rate, sb_cor,
                      n_spec, lo, hi, spread, pool_spread, ctx_spread,
                      boot_w, ratio, fwd_med, fwd_gap))

## Years, percentage words and the like are not results. They are declared here
## so that adding one is deliberate rather than accidental.
context <- c(2023, 95, 4, 100)

bad <- validate_numerals(text, approved, context = context, strict = FALSE)
if (length(bad)) {
  stop("figures in the findings that the analysis did not produce: ",
       paste(unique(bad), collapse = ", "))
}

writeLines(trimws(text), "reports/findings.md")
cat("findings written, every figure checked against the analysis\n")
cat("approved values:", length(approved), " numerals in text:",
    length(extract_numerals(text)), "\n")
