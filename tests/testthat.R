library(testthat)

for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)

test_dir("tests/testthat", stop_on_failure = TRUE)
