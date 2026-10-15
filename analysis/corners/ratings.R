## How dangerous is a corner, for this team, against this team, on this day?
##
## Attack: xG the team made from its corners in earlier games. Defence: xG the
## opponent conceded from corners in earlier games. Each earlier game counts in
## proportion to how many of today's starting eleven also started it, so a side
## that has turned over its squad does not carry an old reputation. Last 25
## games only, earlier games only, and both ratings pulled towards the average
## by how much evidence there is. Then the test that matters: does it predict
## the corners in the game itself better than the flat average does?
##
## Reads what analysis/corners/pull.py wrote and saves cache/corner_ratings.rds,
## which analysis/05, 06 and 07 need. Run it from the repository root.

k <- read.csv("data-raw/ext/women_corners.csv", stringsAsFactors = FALSE)
k$date <- as.Date(k$date)
k$xi <- strsplit(ifelse(is.na(k$xi), "", k$xi), " ")
k$opp_xi <- strsplit(ifelse(is.na(k$opp_xi), "", k$opp_xi), " ")
mu <- sum(k$corner_xg) / sum(k$corners)
cat("team-matches:", nrow(k), " corners:", sum(k$corners), " xG per corner:", round(mu, 4), "\n")

## balance point for shrinkage, from the spread of team averages over pure noise
shrink_k <- function(xg, n) {
  keep <- n >= 10
  per <- xg[keep] / n[keep]
  noise <- mean(0.100^2 / n[keep])   # 0.100 xG: the sd of one corner, measured earlier
  tau2 <- max(stats::var(per) - noise, 1e-6)
  0.100^2 / tau2
}
att_tot <- aggregate(cbind(corner_xg, corners) ~ team, data = k, FUN = sum)
def_tot <- aggregate(cbind(corner_xg, corners) ~ opponent, data = k, FUN = sum)
k_att <- shrink_k(att_tot$corner_xg, att_tot$corners)
k_def <- shrink_k(def_tot$corner_xg, def_tot$corners)
cat("shrinkage balance point: attack", round(k_att), "corners, defence", round(k_def), "corners\n")

overlap <- function(a, b) if (length(a) && length(b)) length(intersect(a, b)) / length(a) else 0

rate <- function(rows, today_xi, which_xi, kk, weighted = TRUE) {
  if (!nrow(rows)) return(c(rating = mu, n_eff = 0))
  rows <- rows[order(rows$date, decreasing = TRUE)[seq_len(min(25, nrow(rows)))], ]
  w <- if (weighted) vapply(rows[[which_xi]], function(x) overlap(today_xi, x), numeric(1)) else rep(1, nrow(rows))
  n_eff <- sum(w * rows$corners)
  if (n_eff == 0) return(c(rating = mu, n_eff = 0))
  raw <- sum(w * rows$corner_xg) / n_eff
  c(rating = mu + n_eff / (n_eff + kk) * (raw - mu), n_eff = n_eff)
}

res <- lapply(seq_len(nrow(k)), function(i) {
  r <- k[i, ]
  prev_att <- k[k$team == r$team & k$date < r$date, ]
  prev_def <- k[k$opponent == r$opponent & k$date < r$date, ]
  a  <- rate(prev_att, r$xi[[1]], "xi", k_att)
  dd <- rate(prev_def, r$opp_xi[[1]], "opp_xi", k_def)
  a0 <- rate(prev_att, r$xi[[1]], "xi", k_att, weighted = FALSE)
  d0 <- rate(prev_def, r$opp_xi[[1]], "opp_xi", k_def, weighted = FALSE)
  c(att = a[["rating"]], att_n = a[["n_eff"]], def = dd[["rating"]], def_n = dd[["n_eff"]],
    att_team = a0[["rating"]], def_team = d0[["rating"]])
})
k <- cbind(k, do.call(rbind, res))
k$matchup <- mu + (k$att - mu) + (k$def - mu)
k$matchup_team <- mu + (k$att_team - mu) + (k$def_team - mu)

## out of sample: the rating uses only earlier games, so compare it with what
## the corners in THIS game produced, weighting each game by its corners
t <- k[k$corners > 0, ]
obs <- t$corner_xg / t$corners
wmse <- function(pred) sum(t$corners * (obs - pred)^2) / sum(t$corners)
base <- wmse(rep(mu, nrow(t)))
cat("\nweighted squared error per corner, lower is better (flat average =", signif(base, 4), ")\n")
for (p in c("att", "def", "matchup", "att_team", "def_team", "matchup_team")) {
  e <- wmse(t[[p]])
  cat(sprintf("  %-13s %.6g   improvement on flat: %+.2f%%\n", p, e, 100 * (base - e) / base))
}
cat("\nshare of team-matches with any earlier history:", round(mean(k$att_n > 0), 3), "\n")
cat("rating spread (5th to 95th percentile): attack", paste(round(quantile(k$att, c(.05, .95)), 3), collapse = " to "),
    "  defence", paste(round(quantile(k$def, c(.05, .95)), 3), collapse = " to "), "\n")
saveRDS(k[, c("match_id", "team", "opponent", "date", "att", "def", "matchup", "att_n", "def_n")],
        "cache/corner_ratings.rds")
