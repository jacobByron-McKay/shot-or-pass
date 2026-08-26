## Build the shot table from raw StatsBomb files and cache it.
##
## Run this first. It downloads roughly 500 MB on a cold start.

source("R/geometry.R")
source("R/statsbomb.R")
source("R/features.R")

library(jsonlite)

matches <- sb_matches()
ids <- vapply(matches, function(m) m$match_id, numeric(1))
cat("matches in the tournament:", length(ids), "\n")

if (!file.exists(sb_path("events", paste0(ids[1], ".json")))) {
  cat("raw data not found, fetching\n")
  fetch_all()
}

shots <- build_shots(ids)

cat("shots:", nrow(shots), "\n")
cat("with at least one forward option:",
    sprintf("%.1f%%", 100 * mean(vapply(shots$options, nrow, integer(1)) > 0)), "\n")
cat("mean options per shot:",
    round(mean(vapply(shots$options, nrow, integer(1))), 2), "\n")
cat("median forward visibility:",
    sprintf("%.1f%%", 100 * median(shots$forward_visible, na.rm = TRUE)), "\n")

dir.create("cache", showWarnings = FALSE)
saveRDS(shots, "cache/shots.rds")
cat("written to cache/shots.rds\n")
