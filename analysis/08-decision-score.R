## The decision score on every shot in the open data with an event freeze
## frame, and the two tests that say whether it belongs to the player.
##
## Split-half: cut each player's shots in two at random and see whether the
## halves agree. Season to season: see whether one season predicts the next. A
## number that fails both is luck, however good it looks in a table.
##
## Needs the shot files from `python analysis/decision/pull.py`. The women's
## shots are the headline set, 13 competition-seasons, so a season can be
## checked against the next. The men's are one season per league, so they get
## split-half only, and the two are never pooled.

source("R/geometry.R")
source("R/features.R")
source("R/value.R")
source("R/report.R")
source("R/decision.R")

women_file <- "data-raw/ext/women_shots.jsonl"
men_file <- "data-raw/ext/men_shots.jsonl"
if (!file.exists(women_file)) {
  stop("no shot file at ", women_file, ": run `python analysis/decision/pull.py` first",
       call. = FALSE)
}

build <- function(path, strata = NULL) {
  t0 <- proc.time()[["elapsed"]]
  s <- with_event_frames(read_shot_file(path))
  sc <- score_decisions(s)
  loc <- fit_location(sc, strata)
  out <- decision_score(sc, loc)
  cat(sprintf("%s: %d shots with a freeze frame, scored in %.0f s\n", path, nrow(out),
              proc.time()[["elapsed"]] - t0))
  attr(out, "location_r2") <- 1 - loc$deviance / loc$null.deviance
  out
}

reliability <- function(d, key, min_split = 40, min_season = 20) {
  set.seed(20260925)
  sh <- split_half(d$decision, key, min_split)
  set.seed(20260925)
  wp <- split_half(d$decision, key, min_split, group = d$group)
  ss <- if (length(unique(d$start_year)) > 1) {
    season_to_season(d$decision, key, d$start_year, min_season)
  } else list(pairs = 0, r = NA_real_)
  data.frame(shots = nrow(d), players_40 = sh$players,
             should_pass = 100 * mean(d$should_pass),
             location_r2 = attr(d, "location_r2"),
             split_half = sh$r, shots_to_trust = shots_to_trust(sh$r, sh$shots_per_half),
             split_half_within_position = wp$r,
             shots_to_trust_within_position = shots_to_trust(wp$r, wp$shots_per_half),
             season_pairs = ss$pairs, season_to_season = ss$r)
}

women <- build(women_file)
rel <- cbind(data = "women", reliability(women, women$player_id))

if (file.exists(men_file)) {
  men <- build(men_file, strata = "competition")
  rel <- rbind(rel, cbind(data = "men", reliability(men, paste(men$competition, men$player_id))))
} else {
  cat("no men's shot file, so no replication this run\n")
}
print(transform(rel[, -1], should_pass = round(should_pass, 1), location_r2 = round(location_r2, 3),
                split_half = round(split_half, 2), shots_to_trust = round(shots_to_trust),
                split_half_within_position = round(split_half_within_position, 2),
                shots_to_trust_within_position = round(shots_to_trust_within_position),
                season_to_season = round(season_to_season, 2)), row.names = FALSE)

## Player tables carry names, so they stay in cache/ and are never committed.
dir.create("cache", showWarnings = FALSE)
players <- player_scores(women, min_shots = 30)
write.csv(players, "cache/decision-score-women.csv", row.names = FALSE)
saveRDS(women[, setdiff(names(women), c("options", "behind"))], "cache/decision-score-women.rds")
if (exists("men")) {
  men$key <- paste(men$competition, men$player_id)
  write.csv(player_scores(men, min_shots = 50, by = "key"), "cache/decision-score-men.csv",
            row.names = FALSE)
}

## The write-up, through the same gate as reports/findings.md.
w <- rel[rel$data == "women", ]
n_shots   <- w$shots
n_comps   <- length(unique(paste(women$competition, women$season)))
n_players <- length(unique(women$player_id))
n_30      <- nrow(players)
sp_share  <- round(w$should_pass, 1)
loc_r2    <- round(100 * w$location_r2, 1)
sh        <- round(w$split_half, 2)
ss        <- round(w$season_to_season, 2)
need      <- round(w$shots_to_trust)
pairs     <- w$season_pairs
p40       <- w$players_40
sh_pos    <- round(w$split_half_within_position, 2)
need_pos  <- round(w$shots_to_trust_within_position)

big <- function(x) format(x, big.mark = ",")
men_text <- ""
approved_men <- numeric()
if (any(rel$data == "men")) {
  m <- rel[rel$data == "men", ]
  approved_men <- c(m$shots, m$players_40, round(m$split_half, 2), round(m$shots_to_trust))
  men_text <- sprintf('
## The men\'s replication

The same score on %s men\'s shots: the Premier League and La Liga in 2015/16,
and Leverkusen\'s matches in 2023/24. One season per league, so split-half
only. Across %d players with 40 or more shots the halves agree at %s, and it
takes about %s shots to trust a player\'s score. Weaker than the women\'s, on a
smaller set, and kept separate from it.
', big(m$shots), m$players_40, sprintf("%.2f", m$split_half), round(m$shots_to_trust))
}

text <- sprintf('
# The decision score

How often a player shoots when a better pass was on, less how often a typical
player shooting from the same spots would. Below zero is the better decider.
It is read within position, because where a player stands explains a lot of
it.

## On every women\'s shot in the open data

%s shots with a freeze frame, from %d competition-seasons and %s players.
A pass was the better option on %s%% of them. Distance, angle and headers
explain %s%% of that; the decision score is what is left.

Across %d players with 40 or more shots, the two halves of a player\'s shots
agree at %s, and a player needs about %s shots before the score can be
trusted. One season predicts the next at %s, over %d pairs of seasons.

Read within position, the halves agree at %s, which takes about %s shots.
That is the honest figure for comparing two forwards.
%s
Data: StatsBomb open data.
', big(n_shots), n_comps, big(n_players), sp_share, loc_r2, p40, sprintf("%.2f", sh), need,
   sprintf("%.2f", ss), pairs, sprintf("%.2f", sh_pos), need_pos, men_text)

approved <- approve(c(n_shots, n_comps, n_players, sp_share, loc_r2, p40, sh, need, ss, pairs,
                      sh_pos, need_pos, approved_men))
## The qualifying cut and the seasons named in the text are not results.
context <- c(40, 2015, 16, 2023, 24)

bad <- validate_numerals(text, approved, context = context, strict = FALSE)
if (length(bad)) {
  stop("figures in the decision score write-up that the analysis did not produce: ",
       paste(unique(bad), collapse = ", "))
}

dir.create("reports", showWarnings = FALSE)
writeLines(trimws(text), "reports/decision-score.md")
write.csv(transform(rel, should_pass = round(should_pass, 2), location_r2 = round(location_r2, 4),
                    split_half = round(split_half, 3), shots_to_trust = round(shots_to_trust, 1),
                    split_half_within_position = round(split_half_within_position, 3),
                    shots_to_trust_within_position = round(shots_to_trust_within_position, 1),
                    season_to_season = round(season_to_season, 3)),
          "reports/decision-score.csv", row.names = FALSE)
cat("written to reports/decision-score.md and reports/decision-score.csv, every figure checked\n")
