## The camera hypothesis, run properly.
##
## The claim was that when less of the pitch ahead of a shooter is on screen,
## fewer of their options get recorded, so the shot ends up looking more justified
## than it was. A single regression said no. A single regression saying no is
## not worth much, so this runs it across every plausible model, control set and
## subset and looks at the whole distribution.
##
## specr is the right tool here because this half of the problem genuinely is a
## regression specification curve, which is what specr was built for. The
## harness in R/multiverse.R covers the other half, the choices made while
## constructing the numbers in the first place, which specr does not model. See
## Steegen et al. (2016) on the data multiverse, the versions of the data that
## defensible processing choices produce.

source("R/geometry.R")
source("R/statsbomb.R")
source("R/features.R")
source("R/value.R")
source("R/multiverse.R")

library(specr)

shots <- readRDS("cache/shots.rds")
res <- readRDS("cache/results.rds")

d <- score_shots(shots, res$model, OPTION_POOLS$ahead,
                 COMPLETION_MODELS$pressure, use_context = TRUE)
d <- d[!is.na(d$forward_visible), ]

d$shot_was_right <- as.numeric(d$edge > 0)
d$band <- cut(d$distance, c(0, 12, 18, Inf),
              labels = c("close", "mid", "long"))
d$phase <- ifelse(d$play_pattern == "Regular Play", "open play", "set piece")
d$half  <- ifelse(d$minute <= 45, "first half", "second half")

cat("shots with a visibility measure:", nrow(d), "\n")

specs <- setup(
  data = d,
  y = c("edge", "shot_was_right"),
  x = c("forward_visible"),
  model = c("lm"),
  controls = c("distance", "angle", "defenders_in_cone"),
  subsets = list(band = levels(d$band),
                 phase = unique(d$phase),
                 half = unique(d$half))
)

cat("\nspecifications:", nrow(specs$specs), "\n")

curve <- specr(specs)
res_tbl <- as.data.frame(curve$data)

## The coefficient on forward visibility, across every specification.
est <- res_tbl$estimate
sig <- res_tbl$p.value < 0.05
pos <- est > 0

cat("\ncoefficient on forward visibility across all specifications\n")
cat("  median:", signif(median(est), 3), "\n")
cat("  range: ", signif(min(est), 3), "to", signif(max(est), 3), "\n")
cat("  share significant at 0.05:", sprintf("%.1f%%", 100 * mean(sig)), "\n")
cat("  share pointing the way the hypothesis predicted (negative):",
    sprintf("%.1f%%", 100 * mean(!pos)), "\n")
cat("  significant AND in the predicted direction:",
    sprintf("%.1f%%", 100 * mean(sig & !pos)), "\n")

png("reports/visibility-specification-curve.png", width = 2000, height = 1400, res = 180)
print(plot(curve, choices = c("x", "y", "controls", "subsets")))
invisible(dev.off())
cat("\ncurve written to reports/visibility-specification-curve.png\n")

write.csv(res_tbl[, c("x", "y", "controls", "subsets", "estimate",
                      "std.error", "p.value", "fit_nobs")],
          "reports/visibility-specifications.csv", row.names = FALSE)

saveRDS(curve, "cache/visibility-curve.rds")
