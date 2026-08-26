## The question the repository exists to answer: of the choices made while
## building this analysis, which ones actually move the conclusion?

source("R/geometry.R")
source("R/statsbomb.R")
source("R/features.R")
source("R/value.R")
source("R/multiverse.R")

shots <- readRDS("cache/shots.rds")
cat("shots:", nrow(shots), "\n")

## The shot value model, and what the freeze frames add to it.
with_context <- fit_shot_value(shots, context = TRUE)
no_context   <- fit_shot_value(shots, context = FALSE)

cat("\nshot value model\n")
print(round(summary(with_context)$coefficients, 4))
cat("\nAIC with defenders in cone:", round(AIC(with_context), 1),
    " without:", round(AIC(no_context), 1), "\n")
cat("likelihood ratio test p:",
    format.pval(anova(no_context, with_context, test = "LRT")$`Pr(>Chi)`[2], digits = 3), "\n")

pred <- stats::predict(with_context, type = "response")
cat("observed goal rate:", round(mean(shots$goal), 4),
    " mean predicted:", round(mean(pred), 4),
    " correlation with StatsBomb xG:", round(cor(pred, shots$statsbomb_xg), 3), "\n")

cat("\ncalibration by decile of predicted value\n")
dec <- cut(pred, quantile(pred, seq(0, 1, 0.1)), include.lowest = TRUE, labels = FALSE)
print(data.frame(
  decile   = 1:10,
  n        = as.integer(table(dec)),
  predicted = round(tapply(pred, dec, mean), 3),
  observed  = round(tapply(shots$goal, dec, mean), 3)
), row.names = FALSE)

## Four decision points. Each one is a question somebody has to answer to get a
## number out, and each has more than one defensible answer.
choices <- list(
  option_pool = OPTION_POOLS,
  completion  = COMPLETION_MODELS,
  receiver_context = list(`360` = TRUE, `distance only` = FALSE),
  margin = list(`any edge` = 0, `clear edge` = 0.02)
)

cat("\nrunning", nrow(specifications(choices)), "specifications\n")

mv <- multiverse(choices, function(pick) {
  model <- if (pick$receiver_context) with_context else no_context
  scored <- score_shots(shots, model, pick$option_pool, pick$completion,
                        use_context = pick$receiver_context)
  c(shoot_was_right = 100 * mean(scored$edge > pick$margin),
    mean_edge = mean(scored$edge),
    mean_best_alternative = mean(scored$best_alternative))
})

cat("\nshare of shots where shooting beat the best alternative\n")
cat("  lowest specification: ", sprintf("%.1f%%", min(mv$shoot_was_right)), "\n")
cat("  highest specification:", sprintf("%.1f%%", max(mv$shoot_was_right)), "\n")
cat("  spread:               ", sprintf("%.1f points", diff(range(mv$shoot_was_right))), "\n")

cat("\nwhich decision moves it, largest first\n")
sens <- sensitivity(mv, "shoot_was_right",
                    decisions = names(choices))
print(data.frame(decision = sens$decision, levels = sens$levels,
                 low = round(sens$low, 1), high = round(sens$high, 1),
                 spread = round(sens$spread, 1)), row.names = FALSE)

## The comparison that decides whether any of it is worth reporting: how wide
## is the sampling interval on the same quantity?
mid <- score_shots(shots, with_context, OPTION_POOLS$ahead,
                   COMPLETION_MODELS$pressure, use_context = TRUE)
boot <- bootstrap_spread(mid, function(d) 100 * mean(d$edge > 0), n = 2000)
cat("\nsampling: 95% interval on one fixed specification is",
    sprintf("[%.1f%%, %.1f%%], width %.1f points", boot$low, boot$high, boot$width), "\n")
cat("definitional spread across all specifications:",
    sprintf("%.1f points", diff(range(mv$shoot_was_right))), "\n")
cat("ratio definitional to sampling:",
    round(diff(range(mv$shoot_was_right)) / boot$width, 2), "\n")

dir.create("cache", showWarnings = FALSE)
saveRDS(list(multiverse = mv, sensitivity = sens, bootstrap = boot,
             model = with_context, scored = mid), "cache/results.rds")
write.csv(mv, "reports/specification-curve.csv", row.names = FALSE)
cat("\nwritten to reports/specification-curve.csv\n")
