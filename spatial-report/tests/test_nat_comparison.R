# Run from the repository root. No user data or model fitting is required.
local({
  e <- new.env(parent = globalenv())
  sys.source("spatial-report/spatial_analysis_helpers.R", e)
  sys.source("spatial-report/nat_comparison_helpers.R", e)
  checks <- 0L
  check <- function(value) {
    stopifnot(isTRUE(value))
    checks <<- checks + 1L
  }
  fails <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  eq <- function(a, b) isTRUE(all.equal(a, b, tolerance = 1e-10))
  directory <- tempfile("nat_tests_")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)

  if (!requireNamespace("digest", quietly = TRUE)) {
    # Only for the dependency-free checks: exercise the same checkpoint code
    # using base-R serialization + MD5 instead of the unavailable digest engine.
    e$nat_hash <- function(x) {
      path <- tempfile()
      on.exit(unlink(path))
      saveRDS(x, path, compress = FALSE)
      unname(tools::md5sum(path))
    }
    message("digest unavailable: checkpoint tests use an MD5 test double.")
  }

  area <- c(1, 100, 1000, 10000, 100000, 1000000)
  check(eq(e$nat_area_predictor(area, "log"), as.numeric(scale(log(area / 10000)))))
  check(eq(e$nat_area_predictor(area, "log1p_ha"), as.numeric(scale(log(1 + area / 10000)))))
  check(!eq(e$nat_area_predictor(area, "log"), e$nat_area_predictor(area, "log1p_ha")))
  check(fails(e$nat_area_predictor(c(0, 1))))
  check(fails(e$nat_area_predictor(c(1, Inf))))
  check(fails(e$nat_area_predictor(rep(1, 3))))
  d <- data.frame(final_id = as.character(seq_along(area)), species_id = rep(c("a", "b"), 3),
    species = factor(rep(c("A", "B"), 3)), mapping = factor(rep(c("broad", "narrow"), 3)),
    quality = factor(rep(c("High", "Medium", "Low"), 2)),
    FPCA1_z = as.numeric(scale(c(2, -1, 3, 6, 1, 2))), area_sq_m = area,
    log_area_z = e$nat_area_predictor(area, "log"),
    point_X_km = 1:6, point_Y_km = c(4, 8, 3, 10, 9, 2),
    centroid_X_km = 1:6 + .1, centroid_Y_km = c(4, 8, 3, 10, 9, 2) + .1)
  saved <- list(model_data = d, parameters = list(merge_variant = "10m", analysis_crs = 25832),
                generated = "test")
  path <- file.path(directory, "input.rds")
  saveRDS(saved, path)
  prepared <- e$nat_read_prepared(path, "10m", 25832)
  check(identical(prepared$data, d))
  check(identical(readRDS(path), saved))
  check(fails(e$nat_read_prepared(saved, "zero", 25832)))
  check(fails(e$nat_read_prepared(saved, "10m", 4326)))
  broken <- saved; broken$model_data <- rbind(d, d[1, ])
  check(fails(e$nat_read_prepared(broken, "10m", 25832)))
  broken <- saved; broken$model_data$log_area_z <- e$nat_area_predictor(area, "log1p_ha")
  check(fails(e$nat_read_prepared(broken, "10m", 25832)))
  broken <- saved; broken$model_data$point_X_km[1] <- Inf
  check(fails(e$nat_read_prepared(broken, "10m", 25832)))

  # Centering/scaling both coordinate axes preserves x + y + x:y predictions.
  coords <- e$nat_coordinates(d, c("point_X_km", "point_Y_km"), 25832, 25832)
  raw_fit <- lm(FPCA1_z ~ point_X_km * point_Y_km, d)
  scaled_fit <- lm(FPCA1_z ~ trend_x * trend_y, cbind(d, coords))
  check(eq(unname(fitted(raw_fit)), unname(fitted(scaled_fit))))

  calls <- 0L
  compute <- function() { calls <<- calls + 1L; c(answer = 42) }
  key <- list(input = prepared$input_key, setting = 1)
  check(identical(e$nat_checkpoint(directory, "test", key, compute), c(answer = 42)))
  check(identical(e$nat_checkpoint(directory, "test", key, compute), c(answer = 42)))
  check(calls == 1L)
  changed <- key; changed$setting <- 2
  e$nat_checkpoint(directory, "test", changed, compute)
  check(calls == 2L)
  failed_key <- list(setting = "failure")
  check(fails(e$nat_checkpoint(directory, "failed", failed_key, function() stop("intentional"))))
  check(!file.exists(e$nat_checkpoint_path(directory, "failed", failed_key)))
  check(length(list.files(file.path(directory, "checkpoints"), pattern = "pending_")) == 0L)
  corrupt_path <- e$nat_checkpoint_path(directory, "corrupt", key)
  saveRDS(list(key = changed, value = 42), corrupt_path)
  check(fails(e$nat_checkpoint(directory, "corrupt", key, compute)))

  moran <- list(statistic = c(observed = .03, expected = -.01, sd = .02), p.value = .04)
  check(identical(e$moran_test_values(moran),
    list(moran_observed = .03, moran_expected = -.01, p_value = .04)))
  check(fails(e$moran_test_values(list(estimate = moran$statistic, p.value = .04))))
  check(fails(e$moran_test_values(list(statistic = moran$statistic, p.value = numeric()))))
  fit_code_before <- e$nat_function_key(c("nat_fit_comparison", "nat_fit_one", "nat_check_model"))
  test_code_before <- e$nat_function_key("moran_test_values")
  saved_extractor <- e$moran_test_values
  e$moran_test_values <- function(test) stop("changed extraction only")
  check(identical(fit_code_before, e$nat_function_key(c("nat_fit_comparison", "nat_fit_one", "nat_check_model"))))
  check(!identical(test_code_before, e$nat_function_key("moran_test_values")))
  e$moran_test_values <- saved_extractor

  # These are structural fixtures, not fitted sdmTMB models. No optimizer or
  # native TMB serialization is tested by this section.
  real_versions <- e$nat_versions
  e$nat_versions <- function(packages) setNames(rep("test-version", length(packages)), packages)
  model <- structure(list(data = d, formula = list(e$nat_model_formula()),
    version = "test-version", family = gaussian(), spatial = "off"), class = "sdmTMB")
  check(isTRUE(e$nat_check_model(model, d, e$nat_model_formula())))
  model$formula <- e$nat_model_formula()
  check(isTRUE(e$nat_check_model(model, d, e$nat_model_formula())))
  altered <- model; altered$data$FPCA1_z[1] <- 10
  check(fails(e$nat_check_model(altered, d, e$nat_model_formula())))
  altered <- model; altered$data <- d[6:1, ]
  check(fails(e$nat_check_model(altered, d, e$nat_model_formula())))
  altered <- model; altered$data$log_area_z <- e$nat_area_predictor(area, "log1p_ha")
  check(fails(e$nat_check_model(altered, d, e$nat_model_formula())))
  altered <- model; altered$version <- "different"
  check(fails(e$nat_check_model(altered, d, e$nat_model_formula())))
  check(fails(e$nat_check_model(model, d, e$nat_model_formula(TRUE))))
  check(fails(e$nat_check_model(model, d, e$nat_model_formula(), spatial = TRUE)))
  spatial <- model; spatial$spatial <- "on"
  check(isTRUE(e$nat_check_model(spatial, d, e$nat_model_formula(), c("point_X_km", "point_Y_km"), TRUE)))
  spatial$data$point_X_km[1] <- 0
  check(fails(e$nat_check_model(spatial, d, e$nat_model_formula(), c("point_X_km", "point_Y_km"), TRUE)))
  e$nat_versions <- real_versions

  # Parse all report chunks without executing any analysis or loading user data.
  lines <- readLines("spatial-report/05_nat_model_comparison.Rmd")
  starts <- which(grepl("^```\\{r", lines))
  ends <- which(trimws(lines) == "```")
  for (start in starts) {
    check(grepl("cache=FALSE", lines[start], fixed = TRUE))
    finish <- min(ends[ends > start])
    parse(text = lines[seq.int(start + 1L, finish - 1L)])
  }
  check(!any(grepl("cache *= *TRUE|assemble_spatial_analysis_data", lines)))
  for (script in c("spatial_analysis_helpers.R", "nat_comparison_helpers.R", "run_nat_comparison.R")) {
    parse(file = file.path("spatial-report", script))
  }

  if (all(vapply(c("vegan", "dplyr"), requireNamespace, logical(1), quietly = TRUE))) {
    set.seed(21)
    z <- expand.grid(species = factor(letters[1:3]), mapping = factor(c("broad", "narrow")),
                     quality = factor(c("High", "Medium", "Low")), replicate = 1:5)
    z$log_area_z <- rnorm(nrow(z)); z$x <- rnorm(nrow(z)); z$y <- rnorm(nrow(z))
    z$FPCA1_z <- .6 * z$log_area_z + .4 * z$x * z$y + rnorm(nrow(z))
    ours <- e$nat_partition(z, data.frame(x = z$x, y = z$y, xy = z$x * z$y))
    direct <- vegan::varpart(z$FPCA1_z, ~log_area_z, ~species, ~mapping + quality,
                             ~x + y + x:y, data = z)
    r2_column <- grep("^Adj", names(direct$part$indfract), value = TRUE)
    check(length(r2_column) == 1L && nrow(ours$fractions) > 0L)
    check(eq(ours$fractions[[r2_column]], direct$part$indfract[[r2_column]]))
    message("PASS: variance partition matches direct vegan::varpart().")
  } else message("SKIP: vegan/dplyr integration (packages unavailable).")

  if (all(vapply(c("DHARMa", "dplyr", "ape"), requireNamespace, logical(1), quietly = TRUE))) {
    set.seed(22)
    z <- data.frame(X = rep(seq(1, 46, 5), each = 3), Y = rep(c(1, 6, 11), 10))
    simulations <- matrix(rnorm(nrow(z) * 100), nrow(z))
    original <- DHARMa::createDHARMa(simulations, rnorm(nrow(z)), seed = 37)
    cell <- e$assign_spatial_cells(z, c("X", "Y"), 10)
    expected <- DHARMa::recalculateResiduals(original, factor(cell, levels = sort(unique(cell))), seed = 37)
    compact <- e$group_dharma_spatial_residuals(original, z, c("X", "Y"), 10, 37, 100)
    check(eq(compact$grouped_residuals$scaledResiduals, expected$scaledResiduals))
    check(eq(compact$grouped_residuals$simulatedResponse, expected$simulatedResponse))
    check(is.null(compact$grouped_residuals$original))
    check(!anyDuplicated(names(compact$grouped_residuals)))
    check(!"aggregateByGroup" %in% names(compact$grouped_residuals))
    before <- DHARMa::testSpatialAutocorrelation(expected,
      x = compact$locations$X, y = compact$locations$Y, plot = FALSE)
    after <- e$test_grouped_dharma_spatial_residuals(compact)
    check(eq(after$test$statistic, before$statistic))
    check(eq(after$test$p.value, before$p.value))
    message("PASS: compact grouped residuals preserve DHARMa simulations, residuals and Moran test.")
  } else message("SKIP: DHARMa/dplyr/ape integration (packages unavailable).")
  message("PASS: ", checks, " checks; ", R.version.string)
})
