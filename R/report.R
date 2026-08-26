## A gate between the numbers the analysis produced and the numbers that end up
## in the prose describing it.
##
## Every figure quoted in a write-up should be traceable to something the code
## computed. Checking that by eye works until the day it does not, and a wrong
## number in a published summary is far more expensive than a missing one.

#' Pull every numeral out of a block of text.
#'
#' Handles thousands separators, decimals, percentages and negatives.
extract_numerals <- function(text) {
  m <- regmatches(text, gregexpr("-?\\d[\\d,]*\\.?\\d*", text, perl = TRUE))
  out <- gsub(",", "", unlist(m))
  out[nzchar(out)]
}

#' Check that every numeral in `text` appears in the approved set.
#'
#' `approved` is the set of values the analysis actually produced. `context`
#' is for numerals that are not results at all, such as years, a squad size or
#' the number of matches in a tournament. Those have to be declared rather than
#' waved through, so that adding one is a deliberate act.
#'
#' Returns the offending numerals invisibly and, when `strict`, stops.
validate_numerals <- function(text, approved, context = character(), tolerance = 1e-8,
                              strict = TRUE) {
  found <- as.numeric(extract_numerals(text))
  ok <- vapply(found, function(v) {
    any(abs(v - approved) < tolerance) || any(abs(v - as.numeric(context)) < tolerance)
  }, logical(1))
  bad <- found[!ok]
  if (length(bad) && strict) {
    stop("numerals in the text that the analysis did not produce: ",
         paste(unique(bad), collapse = ", "), call. = FALSE)
  }
  invisible(bad)
}

#' Round a value and register both the rounded and unrounded form as approved.
#'
#' Prose quotes rounded figures. Without this the gate rejects the very numbers
#' it is supposed to be protecting, and the temptation is then to loosen the
#' gate rather than to fix the bookkeeping.
approve <- function(...) {
  vals <- unlist(list(...))
  unique(c(vals, round(vals), round(vals, 1), round(vals, 2),
           round(vals, 3), round(vals, 4)))
}
