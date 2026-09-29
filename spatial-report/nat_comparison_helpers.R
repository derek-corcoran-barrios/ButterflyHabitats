# Additional models using the already prepared patch table. Source the current
# spatial_analysis_helpers.R first. Never rebuild geometries in this workflow.

nat_area_predictor <- function(area_sq_m, transformation = c("log", "log1p_ha")) {
  transformation <- match.arg(transformation)
  if (!is.numeric(area_sq_m) || any(!is.finite(area_sq_m) | area_sq_m <= 0)) {
    stop("All saved patch areas must be positive and finite.")
  }
  # log(m2) and log(ha) differ only by a constant. Retain the original m2
  # expression for bit-for-bit compatibility with saved standardized fits.
  value <- if (transformation == "log") log(area_sq_m) else log1p(area_sq_m / 10000)
  if (length(value) < 2L || !is.finite(stats::sd(value)) || stats::sd(value) == 0) {
    stop("The transformed area must have nonzero finite variance.")
  }
  as.numeric(scale(value))
}

nat_hash <- function(x) digest::digest(x, algo = "xxhash64")

nat_function_key <- function(functions) {
  nat_hash(lapply(functions, function(name) {
    fun <- get(name, mode = "function", inherits = TRUE)
    list(name = name, formals = formals(fun), body = body(fun))
  }))
}

nat_versions <- function(packages) {
  setNames(vapply(packages, function(p) as.character(utils::packageVersion(p)),
                  character(1)), packages)
}

nat_log <- function(directory, stage, status) {
  line <- paste(format(Sys.time(), "%Y-%m-%d %H:%M:%S %z"), status, stage, sep = " | ")
  message(line)
  cat(line, "\n", file = file.path(directory, "progress.log"), append = TRUE)
}

nat_checkpoint_path <- function(directory, stage, key) {
  file.path(directory, "checkpoints", paste0(stage, "_", nat_hash(key), ".rds"))
}

nat_checkpoint <- function(directory, stage, key, compute) {
  path <- nat_checkpoint_path(directory, stage, key)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    nat_log(directory, stage, "LOAD")
    item <- readRDS(path)
    if (!identical(item$key, key)) stop("Checkpoint metadata mismatch: ", path)
    return(item$value)
  }
  nat_log(directory, stage, "START")
  value <- tryCatch(compute(), error = function(e) {
    nat_log(directory, stage, paste("ERROR", conditionMessage(e)))
    stop(e)
  })
  temporary <- tempfile("pending_", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  # Ordinary RDS serialization avoids the knitr lazy-load long-vector limit.
  saveRDS(list(key = key, value = value), temporary, compress = FALSE)
  if (file.exists(path) || !file.rename(temporary, path)) {
    stop("Could not commit checkpoint; avoid concurrent runs in the same output directory: ", path)
  }
  nat_log(directory, stage, "DONE")
  value
}

nat_read_prepared <- function(path, merge_variant, analysis_crs) {
  saved <- if (is.character(path)) readRDS(path) else path
  if (!is.list(saved) || !is.data.frame(saved$model_data) || is.null(saved$parameters)) {
    stop("Expected spatial_model_data.rds with model_data and parameters.")
  }
  if (!identical(as.character(saved$parameters$merge_variant), merge_variant) ||
      !isTRUE(all.equal(saved$parameters$analysis_crs, analysis_crs))) {
    stop("Saved merge correction / projected CRS differs from report parameters.")
  }
  data <- as.data.frame(saved$model_data)
  columns <- c("final_id", "species_id", "species", "mapping", "quality",
               "FPCA1_z", "area_sq_m", "log_area_z", "point_X_km", "point_Y_km",
               "centroid_X_km", "centroid_Y_km")
  if (!all(columns %in% names(data)) || !nrow(data)) stop("Incomplete prepared model table.")
  data <- data[columns]
  numeric_columns <- setdiff(columns, c("final_id", "species_id", "species", "mapping", "quality"))
  if (anyNA(data) || !all(vapply(data[numeric_columns], function(x) {
    is.numeric(x) && all(is.finite(x))
  }, logical(1)))) stop("Prepared data contain missing or non-finite model inputs.")
  if (!all(vapply(data[c("species", "mapping", "quality")], is.factor, logical(1)))) {
    stop("Expected saved factor levels for species, mapping, and quality.")
  }
  expected_log <- nat_area_predictor(data$area_sq_m, "log")
  if (!isTRUE(all.equal(data$log_area_z, expected_log, tolerance = 1e-10))) {
    stop("Saved log_area_z does not match standardized log(area_sq_m). Inspect preprocessing.")
  }
  keys <- do.call(paste, c(data[c("species_id", "mapping", "quality", "final_id")], sep = "\r"))
  if (anyDuplicated(keys)) stop("Duplicate species/scenario/patch keys.")
  list(data = data, parameters = saved$parameters, generated = saved$generated,
       input_key = nat_hash(data))
}

nat_coordinates <- function(data, xy_cols, analysis_crs, coordinate_crs) {
  xy <- as.matrix(data[xy_cols])
  # These saved coordinates are in km in analysis_crs. Projection only touches
  # point coordinates; no polygon objects or union operations are required.
  if (coordinate_crs != analysis_crs) {
    xy <- sf::sf_project(sf::st_crs(analysis_crs)$wkt,
                         sf::st_crs(coordinate_crs)$wkt, xy * 1000)
  }
  if (any(!is.finite(xy))) stop("Coordinate transformation produced non-finite values.")
  if (any(apply(xy, 2, stats::sd) == 0)) stop("Coordinate trends need variation in both axes.")
  # With an intercept, x+y+x:y has the same span after centering/scaling x,y.
  xy <- scale(xy)
  data.frame(trend_x = xy[, 1], trend_y = xy[, 2])
}

nat_partition <- function(data, spatial) {
  result <- run_variance_partition(data, list(matrix = as.matrix(spatial)))
  list(table = result$table,
       fractions = varpart_fraction_table(result$varpart, "pending"))
}

nat_rda_comparison <- function(data, input_key, directory, params) {
  outputs <- list()
  supports <- list(point_on_surface = c("point_X_km", "point_Y_km"),
                   centroid = c("centroid_X_km", "centroid_Y_km"))
  for (support in names(supports)) {
    xy_cols <- supports[[support]]
    coord_key <- list(input = input_key, support = support, from = params$analysis_crs,
                      to = params$coordinate_crs, code = nat_function_key("nat_coordinates"),
                      sf = nat_versions("sf"))
    coordinates <- nat_checkpoint(directory, paste0("coordinates_", support), coord_key,
      function() nat_coordinates(data, xy_cols, params$analysis_crs, params$coordinate_crs))
    for (transformation in c("log", "log1p_ha")) {
      dat <- data
      dat$log_area_z <- nat_area_predictor(data$area_sq_m, transformation)
      for (spatial in c("coordinate_trend", "dbMEM")) {
        label <- paste("rda", transformation, support, spatial, sep = "_")
        key <- list(input = input_key, transformation = transformation, coordinates = coord_key,
                    spatial = spatial, seed = params$seed,
                    code = nat_function_key(c("nat_area_predictor", "nat_partition",
                      "run_variance_partition", "adjusted_r2", "varpart_fraction_table")),
                    packages = nat_versions(c("vegan", "dplyr")))
        if (spatial == "dbMEM") {
          key$mem <- params[c("mem_grid_km", "mem_method", "mem_nperm", "mem_nperm_global")]
          key$mem_code <- nat_function_key(c("select_mem_block", "assign_spatial_cells"))
          key$mem_version <- nat_versions(c("adespatial", "spdep", "ade4"))
        }
        result <- nat_checkpoint(directory, label, key, function() {
          set.seed(params$seed)
          if (spatial == "dbMEM") {
            mem <- select_mem_block(dat, xy_cols, grid_km = params$mem_grid_km,
              method = params$mem_method, nperm = params$mem_nperm,
              nperm_global = params$mem_nperm_global)
            result <- nat_partition(dat, mem$matrix)
            result$mem <- data.frame(occupied_cells = nrow(mem$cells),
              positive_MEMs = mem$all_mem_count, selected_MEMs = mem$selected_mem_count)
          } else {
            matrix <- cbind(coordinates, trend_xy = coordinates$trend_x * coordinates$trend_y)
            result <- nat_partition(dat, matrix)
            result$mem <- NULL
          }
          result
        })
        tag <- data.frame(transformation = transformation, support = support,
                          spatial_representation = spatial)
        result$table <- cbind(tag[rep(1L, nrow(result$table)), ], result$table)
        result$fractions$support <- NULL
        result$fractions <- cbind(tag[rep(1L, nrow(result$fractions)), ], result$fractions)
        if (!is.null(result$mem)) result$mem <- cbind(tag, result$mem)
        outputs[[label]] <- result
      }
    }
  }
  result <- list(table = dplyr::bind_rows(lapply(outputs, `[[`, "table")),
                 fractions = dplyr::bind_rows(lapply(outputs, `[[`, "fractions")),
                 mem = dplyr::bind_rows(lapply(outputs, `[[`, "mem")))
  for (name in names(result)) readr::write_csv(result[[name]],
    file.path(directory, paste0("nat_rda_", name, ".csv")))
  result
}

nat_model_formula <- function(coordinate_trend = FALSE) {
  if (coordinate_trend) {
    FPCA1_z ~ log_area_z + mapping + quality + trend_x * trend_y + (1 | species)
  } else {
    FPCA1_z ~ log_area_z + mapping + quality + (1 | species)
  }
}

nat_fit_one <- function(data, formula, mesh = NULL) {
  if (is.null(mesh)) {
    sdmTMB::sdmTMB(formula, data = data, family = stats::gaussian(), spatial = "off")
  } else {
    sdmTMB::sdmTMB(formula, data = data, family = stats::gaussian(), spatial = "on", mesh = mesh)
  }
}

nat_check_model <- function(model, data, formula, xy_cols = NULL, spatial = FALSE) {
  if (!inherits(model, "sdmTMB") || !is.data.frame(model$data)) stop("Invalid saved sdmTMB model.")
  canonical <- function(f) {
    # sdmTMB stores even a single Gaussian formula in a one-element list.
    if (is.list(f) && length(f) == 1L) f <- f[[1L]]
    if (!inherits(f, "formula")) stop("Expected one saved model formula.")
    gsub("[[:space:]]", "", paste(deparse(f), collapse = ""))
  }
  if (!identical(canonical(model$formula), canonical(formula))) stop("Saved model formula differs.")
  if (is.null(model$version) || as.character(model$version) != nat_versions("sdmTMB")[[1L]]) {
    stop("Saved fit uses a different/unknown sdmTMB version. Use its fitting version or choose a fresh run.")
  }
  if (!identical(model$family$family, "gaussian") || !identical(model$family$link, "identity")) {
    stop("Expected a Gaussian identity-link model.")
  }
  columns <- unique(c("final_id", "species_id", all.vars(formula), xy_cols))
  if (!all(columns %in% names(model$data)) || nrow(model$data) != nrow(data)) {
    stop("Saved model lacks matching row-level inputs.")
  }
  for (name in columns) {
    if (!isTRUE(all.equal(model$data[[name]], data[[name]], tolerance = 1e-12))) {
      stop("Saved model input differs: ", name)
    }
  }
  if (!identical(unname(unlist(model$spatial)), if (spatial) "on" else "off")) {
    stop("Saved model spatial setting differs.")
  }
  invisible(TRUE)
}

nat_previous_suite <- function(path, data, xy_cols, directory) {
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  nat_log(directory, basename(path), "CHECK PREVIOUS FITS")
  suite <- readRDS(path)
  expected_names <- paste0("cutoff_", suite$cutoffs_km, "km")
  if (!identical(suite$xy_cols, xy_cols) || is.null(suite$nonspatial) ||
      !length(suite$spatial) || !length(suite$cutoffs_km) ||
      !all(expected_names %in% names(suite$spatial)) ||
      !all(expected_names %in% names(suite$meshes))) {
    stop("Unexpected previous model-suite structure: ", path)
  }
  nat_check_model(suite$nonspatial, data, nat_model_formula())
  for (fit in suite$spatial) nat_check_model(fit, data, nat_model_formula(), xy_cols, TRUE)
  suite
}

nat_fit_comparison <- function(data, input_key, directory, params) {
  point_cols <- c("point_X_km", "point_Y_km")
  centroid_cols <- c("centroid_X_km", "centroid_Y_km")
  previous <- params$previous_results_dir
  old_point <- nat_previous_suite(if (nzchar(previous)) file.path(previous,
    "spde_point_on_surface_models.rds") else "", data, point_cols, directory)
  old_centroid <- if (isTRUE(params$run_centroid_sensitivity)) nat_previous_suite(
    if (nzchar(previous)) file.path(previous, "spde_centroid_model.rds") else "",
    data, centroid_cols, directory) else NULL
  models <- list(); fixed <- list(); comparisons <- list(); random <- list()
  supports <- list(point_on_surface = point_cols)
  if (isTRUE(params$run_centroid_sensitivity)) supports$centroid <- centroid_cols
  for (support in names(supports)) {
    xy_cols <- supports[[support]]
    cutoffs <- if (support == "centroid") params$primary_cutoff_km else params$mesh_cutoffs_km
    old <- if (support == "centroid") old_centroid else old_point
    coord_key <- list(input = input_key, support = support, from = params$analysis_crs,
                      to = params$coordinate_crs, code = nat_function_key("nat_coordinates"),
                      sf = nat_versions("sf"))
    coordinates <- nat_checkpoint(directory, paste0("coordinates_", support), coord_key,
      function() nat_coordinates(data, xy_cols, params$analysis_crs, params$coordinate_crs))
    for (transformation in c("log", "log1p_ha")) {
      dat <- data
      dat$log_area_z <- nat_area_predictor(data$area_sq_m, transformation)
      dat$trend_x <- coordinates$trend_x; dat$trend_y <- coordinates$trend_y
      # A coordinate-free baseline is shared between support representations.
      kinds <- if (support == "centroid") paste0("SPDE_", cutoffs) else {
        c("nonspatial", "coordinate_trend", paste0("SPDE_", cutoffs))
      }
      for (kind in kinds) {
        spatial <- startsWith(kind, "SPDE_")
        cutoff <- if (spatial) as.numeric(sub("SPDE_", "", kind)) else NA_real_
        label <- paste(transformation, support, kind, sep = "_")
        formula <- nat_model_formula(kind == "coordinate_trend")
        key <- list(input = input_key, transformation = transformation, support = support,
          kind = kind, formula = paste(deparse(formula), collapse = ""),
          coordinate_crs = if (kind == "coordinate_trend") params$coordinate_crs else NULL,
          cutoff = cutoff, seed = params$seed,
          code = nat_function_key(c("nat_area_predictor", "nat_model_formula", "nat_fit_one")),
          packages = nat_versions(c("sdmTMB", "TMB", "fmesher")))
        if (kind == "coordinate_trend") key$coordinates <- coord_key
        model <- nat_checkpoint(directory, paste0("fit_", label), key, function() {
          candidate <- NULL
          if (transformation == "log" && !is.null(old)) {
            if (kind == "nonspatial") candidate <- old$nonspatial
            if (spatial && cutoff %in% old$cutoffs_km) {
              candidate <- old$spatial[[paste0("cutoff_", cutoff, "km")]]
            }
          }
          if (!is.null(candidate)) {
            nat_check_model(candidate, dat, formula, if (spatial) xy_cols else NULL, spatial)
            nat_log(directory, label, "REUSE PREVIOUS FIT")
            return(candidate)
          }
          set.seed(params$seed)
          mesh <- NULL
          if (spatial) {
            mesh_key <- list(input = input_key, support = support, cutoff = cutoff,
                              seed = params$seed, packages = nat_versions(c("sdmTMB", "fmesher")))
            mesh <- nat_checkpoint(directory, paste0("mesh_", support, "_", cutoff), mesh_key,
              function() {
                if (!is.null(old) && cutoff %in% old$cutoffs_km) {
                  old$meshes[[paste0("cutoff_", cutoff, "km")]]
                } else sdmTMB::make_mesh(dat, xy_cols = xy_cols, cutoff = cutoff)
              })
          }
          nat_fit_one(dat, formula, mesh)
        })
        tag <- data.frame(transformation = transformation, support = support,
                          model = kind, cutoff_km = cutoff)
        tidy <- as.data.frame(sdmTMB::tidy(model, conf.int = TRUE))
        fixed[[label]] <- cbind(tag[rep(1L, nrow(tidy)), ], tidy)
        comparisons[[label]] <- cbind(tag, AIC = stats::AIC(model),
          convergence = if (length(model$model$convergence)) model$model$convergence else NA_integer_,
          pdHess = if (length(model$sd_report$pdHess)) model$sd_report$pdHess else NA)
        if (spatial) {
          pars <- as.data.frame(sdmTMB::tidy(model, effects = "ran_pars", conf.int = TRUE))
          random[[label]] <- cbind(tag[rep(1L, nrow(pars)), ], pars)
        }
        sanity <- utils::capture.output(sdmTMB::sanity(model))
        writeLines(sanity, file.path(directory, paste0("sanity_", label, ".txt")))
        # Keep references to checkpoints, not all multi-million-row fitted objects.
        models[[label]] <- list(path = nat_checkpoint_path(directory, paste0("fit_", label), key),
                               key = key, tag = tag)
        # Write incremental tables so partial progress is available after a failure.
        readr::write_csv(dplyr::bind_rows(fixed), file.path(directory, "nat_fixed_effects.csv"))
        readr::write_csv(dplyr::bind_rows(comparisons), file.path(directory, "nat_model_aic.csv"))
        rm(model)
      }
    }
  }
  aic <- dplyr::bind_rows(comparisons)
  aic$delta_AIC <- aic$AIC - min(aic$AIC)
  result <- list(models = models, fixed = dplyr::bind_rows(fixed), aic = aic,
                 random = dplyr::bind_rows(random))
  readr::write_csv(aic, file.path(directory, "nat_model_aic.csv"))
  readr::write_csv(result$random, file.path(directory, "nat_random_parameters.csv"))
  result
}

nat_fit_summary <- function(data, input_key, directory, params) {
  key <- list(input = input_key,
    params = params[c("analysis_crs", "coordinate_crs", "mesh_cutoffs_km", "primary_cutoff_km",
                       "run_centroid_sensitivity", "seed")],
    code = nat_function_key(c("nat_area_predictor", "nat_coordinates", "nat_fit_comparison",
      "nat_model_formula", "nat_fit_one", "nat_check_model", "nat_previous_suite")),
    packages = nat_versions(c("sdmTMB", "TMB", "fmesher", "sf")))
  result <- nat_checkpoint(directory, "fit_summary", key,
                           function() nat_fit_comparison(data, input_key, directory, params))
  for (name in c("fixed", "aic", "random")) {
    path <- switch(name, fixed = "nat_fixed_effects.csv", aic = "nat_model_aic.csv",
                   random = "nat_random_parameters.csv")
    readr::write_csv(result[[name]], file.path(directory, path))
  }
  # The saved summary only refers to model paths. Detect missing files before
  # expensive residual work; do not silently launch replacement model fits.
  if (!all(vapply(result$models, function(x) file.exists(x$path), logical(1)))) {
    stop("A model checkpoint referenced by fit_summary is missing. Restore the checkpoint directory.")
  }
  result
}

nat_residual_comparison <- function(models, data, input_key, directory, params) {
  results <- list()
  labels <- names(models)[vapply(models, function(x) {
    x$tag$support == "point_on_surface" && x$tag$model %in%
      c("nonspatial", paste0("SPDE_", params$primary_cutoff_km))
  }, logical(1))]
  for (label in labels) {
    entry <- models[[label]]
    key <- list(model = entry$key, input = input_key, seed = params$seed,
      nsim = params$residual_nsim, grids = params$residual_grid_km,
      code = nat_function_key(c("make_dharma_residuals", "group_dharma_spatial_residuals",
                                "assign_spatial_cells")),
      packages = nat_versions(c("sdmTMB", "DHARMa", "TMB")))
    groups <- nat_checkpoint(directory, paste0("grouped_residuals_", label), key, function() {
      model <- readRDS(entry$path)$value
      # The sdmTMB simulate method reinitializes saved TMB objects itself.
      residuals <- make_dharma_residuals(model, nsim = params$residual_nsim, seed = params$seed)
      lapply(params$residual_grid_km, function(grid) group_dharma_spatial_residuals(
        residuals, data, c("point_X_km", "point_Y_km"), grid, params$seed, params$residual_nsim))
    })
    # Grouped simulations are committed BEFORE Moran testing. A later table/test
    # fix reruns only these tests, not fitting or the expensive simulations.
    test_key <- list(groups = key,
      code = nat_function_key(c("moran_test_values", "test_grouped_dharma_spatial_residuals")),
      packages = nat_versions(c("DHARMa", "ape")))
    tables <- nat_checkpoint(directory, paste0("moran_tests_", label), test_key, function() {
      dplyr::bind_rows(lapply(groups, function(g) test_grouped_dharma_spatial_residuals(g)$table))
    })
    results[[label]] <- cbind(entry$tag[rep(1L, nrow(tables)), ], tables)
    readr::write_csv(dplyr::bind_rows(results), file.path(directory, "nat_residual_moran.csv"))
  }
  dplyr::bind_rows(results)
}
