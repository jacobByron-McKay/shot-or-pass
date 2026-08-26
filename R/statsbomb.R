## Reading StatsBomb open data off disk, and fetching it if it is not there.
##
## Data source: StatsBomb open data, https://github.com/statsbomb/open-data
## Nothing is committed to this repository. See README for the licence terms.

SB_RAW <- "https://raw.githubusercontent.com/statsbomb/open-data/master/data"

#' Which competition and season this project uses.
#'
#' Competition 72 season 107 is the 2023 FIFA Women's World Cup, the most
#' recent tournament in the open data with complete 360 coverage.
WWC_2023 <- list(competition_id = 72, season_id = 107)

sb_path <- function(...) file.path("data-raw", ...)

download_json <- function(url, dest) {
  dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
  utils::download.file(url, dest, quiet = TRUE, mode = "wb")
  invisible(dest)
}

#' Match list for the tournament, downloading it on first use.
sb_matches <- function(comp = WWC_2023) {
  dest <- sb_path("matches.json")
  if (!file.exists(dest)) {
    download_json(sprintf("%s/matches/%d/%d.json", SB_RAW,
                          comp$competition_id, comp$season_id), dest)
  }
  jsonlite::fromJSON(dest, simplifyDataFrame = FALSE)
}

#' Events for one match.
sb_events <- function(match_id) {
  dest <- sb_path("events", paste0(match_id, ".json"))
  if (!file.exists(dest)) {
    download_json(sprintf("%s/events/%s.json", SB_RAW, match_id), dest)
  }
  jsonlite::fromJSON(dest, simplifyDataFrame = FALSE)
}

#' Freeze frames for one match, keyed by the event id they belong to.
#'
#' Each frame holds the positions of the players the broadcast camera could
#' see, flagged as teammate or opponent relative to the player on the ball.
#' There are no player identities in a frame, only those flags.
sb_frames <- function(match_id) {
  dest <- sb_path("three-sixty", paste0(match_id, ".json"))
  if (!file.exists(dest)) {
    download_json(sprintf("%s/three-sixty/%s.json", SB_RAW, match_id), dest)
  }
  raw <- jsonlite::fromJSON(dest, simplifyDataFrame = FALSE)
  stats::setNames(raw, vapply(raw, function(f) f$event_uuid, character(1)))
}

#' Fetch everything the analysis needs. Roughly 500 MB and a few minutes.
fetch_all <- function(comp = WWC_2023) {
  ms <- sb_matches(comp)
  ids <- vapply(ms, function(m) m$match_id, numeric(1))
  for (i in seq_along(ids)) {
    sb_events(ids[i])
    sb_frames(ids[i])
    cat(sprintf("\r%d/%d matches", i, length(ids)))
  }
  cat("\n")
  invisible(ids)
}

#' The visible area polygon as a two column matrix.
#'
#' StatsBomb store it as a flat vector of alternating x and y values.
visible_polygon <- function(frame) {
  v <- unlist(frame$visible_area)
  if (length(v) < 6) return(matrix(numeric(0), ncol = 2))
  matrix(v, ncol = 2, byrow = TRUE)
}
