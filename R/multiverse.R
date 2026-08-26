## Run an analysis under every defensible version of every choice in it.
##
## The argument this repository is making is that you cannot tell by reasoning
## which of your choices your conclusion depends on. You have to run them all
## and look.

#' Every combination of the supplied choices.
#'
#' `choices` is a named list of named lists. Each outer name is a decision
#' point in the analysis, each inner name is one defensible way of settling it.
specifications <- function(choices) {
  grid <- expand.grid(lapply(choices, names), stringsAsFactors = FALSE,
                      KEEP.OUT.ATTRS = FALSE)
  grid[order(apply(grid, 1, paste, collapse = "")), , drop = FALSE]
}

#' Run `evaluate` once per specification.
#'
#' `evaluate` receives a named list holding one selected value per decision
#' point, and returns a named numeric vector of results. The returned frame has
#' one row per specification with the choices alongside the results, which is
#' what a specification curve is drawn from.
multiverse <- function(choices, evaluate, verbose = TRUE) {
  grid <- specifications(choices)
  out <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    picked <- lapply(names(choices), function(cp) choices[[cp]][[grid[[cp]][i]]])
    names(picked) <- names(choices)
    out[[i]] <- as.data.frame(as.list(evaluate(picked)))
    if (verbose) cat(sprintf("\r%d/%d specifications", i, nrow(grid)))
  }
  if (verbose) cat("\n")
  cbind(grid, do.call(rbind, out), row.names = NULL)
}

#' How much each decision point moves a result, holding the others as they lie.
#'
#' The spread column is the gap between the best and worst outcome you would
#' report depending purely on how that one decision went. A choice with a large
#' spread has to be disclosed. A choice with a small one can be settled however
#' you like and forgotten about.
sensitivity <- function(mv, outcome, decisions = NULL) {
  decisions <- decisions %||% setdiff(names(mv), outcome)
  rows <- lapply(decisions, function(d) {
    m <- tapply(mv[[outcome]], mv[[d]], mean)
    data.frame(decision = d,
               levels = length(m),
               low = min(m), high = max(m), spread = max(m) - min(m),
               stringsAsFactors = FALSE)
  })
  res <- do.call(rbind, rows)
  res[order(-res$spread), , drop = FALSE]
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Sampling spread for the same outcome, so the two can be compared honestly.
#'
#' Definitional spread that is small next to sampling noise is not worth
#' reporting. Definitional spread that is larger is the one nobody mentions.
bootstrap_spread <- function(x, statistic, n = 1000, conf = 0.95) {
  n_obs <- if (is.data.frame(x)) nrow(x) else length(x)
  reps <- replicate(n, {
    idx <- sample.int(n_obs, n_obs, replace = TRUE)
    statistic(if (is.data.frame(x)) x[idx, , drop = FALSE] else x[idx])
  })
  q <- stats::quantile(reps, c((1 - conf) / 2, 1 - (1 - conf) / 2), names = FALSE)
  list(low = q[1], high = q[2], width = q[2] - q[1])
}
