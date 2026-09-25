# Helper functions for the manuscript spatial-autocorrelation analysis.
#
# These functions deliberately keep connectivity geometry and residual spatial
# structure separate. Edge-to-edge distances are used upstream to construct
# FPCA scores. Spatial covariates here are derived from representative patch
# locations and are never constructed from the edge-distance response matrix.

required_spatial_packages <- function() {
  c(
    "sf", "dplyr", "readr", "ggplot2",
    "vegan", "adespatial", "sdmTMB", "DHARMa", "knitr"
  )
}

assert_spatial_packages <- function(packages = required_spatial_packages()) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop(
      "Install the packages required by the spatial report: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

normalise_species_id <- function(x) {
  x <- as.character(x)
  x <- sub("^Sorted_", "", x)
  x <- sub("_(broad|narrow)_.*$", "", x)
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_+|_+$", "", x)
}

pretty_species_name <- function(x) {
  x <- gsub("_", " ", normalise_species_id(x), fixed = TRUE)
  tools::toTitleCase(x)
}

parse_scenario <- function(x) {
  x <- as.character(x)
  matched <- regexec("^(broad|narrow)_(High|Medium|Low)$", x)
  pieces <- regmatches(x, matched)
  ok <- lengths(pieces) == 3L
  if (!all(ok)) {
    stop(
      "Scenario names must use '<broad|narrow>_<High|Medium|Low>'. Invalid: ",
      paste(unique(x[!ok]), collapse = ", "),
      call. = FALSE
    )
  }
  data.frame(
    mapping = vapply(pieces, `[[`, character(1), 2L),
    quality = vapply(pieces, `[[`, character(1), 3L),
    stringsAsFactors = FALSE
  )
}

spatial_variant_spec <- function(variant = c("zero", "10m", "20m")) {
  variant <- match.arg(variant)
  switch(
    variant,
    zero = list(
      lookup_prefix = "PolygonToFinal_",
      area_prefix = "PatchAreas_CorrectedSuperpolygons_",
      distance_suffix = "_distances_corrected_superpolygons.rds",
      label = "0 m (touching polygons only)"
    ),
    `10m` = list(
      lookup_prefix = "PolygonToFinal_10m_",
      area_prefix = "PatchAreas_CorrectedSuperpolygons_10m_",
      distance_suffix = "_distances_corrected_superpolygons_10m.rds",
      label = "10 m merge distance"
    ),
    `20m` = list(
      lookup_prefix = "PolygonToFinal_20m_",
      area_prefix = "PatchAreas_CorrectedSuperpolygons_20m_",
      distance_suffix = "_distances_corrected_superpolygons_20m.rds",
      label = "20 m merge distance"
    )
  )
}

read_fpca_patch_scores <- function(results_dir, results_file = NULL) {
  if (is.null(results_file)) {
    results_file <- file.path(results_dir, "patch_fpca_results.rds")
  }
  if (!file.exists(results_file)) {
    stop(
      "Missing patch-level FPCA results: ", results_file,
      ". Run inst/analysis/02_run_fpca.R first.",
      call. = FALSE
    )
  }

  results <- readRDS(results_file)
  if (!is.list(results) || is.null(names(results))) {
    stop("patch_fpca_results.rds must contain a named result list.", call. = FALSE)
  }

  rows <- lapply(names(results), function(scenario) {
    result <- results[[scenario]]
    dat <- result$fpca_patch_df
    if (is.null(dat) || !nrow(dat)) return(NULL)

    score_col <- intersect(c("FPCA1", "PC1"), names(dat))
    id_col <- intersect(c("final_id_1", "final_id", "patch_id"), names(dat))
    if (!length(score_col) || !length(id_col)) {
      stop(
        "Scenario ", scenario,
        " lacks a FPCA1/PC1 score or final patch identifier.",
        call. = FALSE
      )
    }
    score_col <- score_col[[1L]]
    id_col <- id_col[[1L]]

    if ("species_full" %in% names(dat)) {
      species_id <- normalise_species_id(dat$species_full)
    } else if ("species" %in% names(dat)) {
      species_id <- normalise_species_id(dat$species)
    } else {
      stop("Scenario ", scenario, " lacks a species column.", call. = FALSE)
    }

    # PCA signs are arbitrary. Orient FPCA1 so larger scores consistently mean
    # shorter distances / greater structural connectivity. For the observed
    # positive, same-sign PC1 loadings this reverses the raw score sign.
    loadings <- result$loadings
    multiplier <- 1
    if (!is.null(loadings) && ncol(as.matrix(loadings)) >= 1L) {
      mean_loading <- mean(as.matrix(loadings)[, 1L], na.rm = TRUE)
      multiplier <- if (is.finite(mean_loading) && mean_loading > 0) -1 else 1
    } else {
      warning(
        "Scenario ", scenario,
        " has no loadings; FPCA1 sign was retained. Check its interpretation."
      )
    }

    parsed <- parse_scenario(scenario)
    data.frame(
      scenario = scenario,
      mapping = parsed$mapping[[1L]],
      quality = parsed$quality[[1L]],
      species_id = species_id,
      species = if ("species" %in% names(dat)) {
        as.character(dat$species)
      } else {
        pretty_species_name(species_id)
      },
      final_id = as.character(dat[[id_col]]),
      FPCA1_raw = as.numeric(dat[[score_col]]),
      FPCA1 = multiplier * as.numeric(dat[[score_col]]),
      fpca_orientation_multiplier = multiplier,
      stringsAsFactors = FALSE
    )
  })

  scores <- dplyr::bind_rows(rows)
  if (!nrow(scores)) {
    stop("No patch-level FPCA tables were found in the result object.", call. = FALSE)
  }

  key <- c("species_id", "mapping", "quality", "final_id")
  duplicates <- scores |>
    dplyr::count(dplyr::across(dplyr::all_of(key)), name = "n") |>
    dplyr::filter(.data$n > 1L)
  if (nrow(duplicates)) {
    stop(
      "FPCA patch identifiers are duplicated within species/scenario. First duplicate: ",
      paste(unlist(duplicates[1L, key]), collapse = " / "),
      call. = FALSE
    )
  }
  scores
}

scenario_file_stem <- function(species_id, mapping, quality) {
  paste(species_id, mapping, quality, sep = "_")
}

read_final_patch_geometry <- function(
    patch_dir,
    species_id,
    mapping,
    quality,
    merge_variant = c("zero", "10m", "20m"),
    analysis_crs = 25832) {
  merge_variant <- match.arg(merge_variant)
  spec <- spatial_variant_spec(merge_variant)
  stem <- scenario_file_stem(species_id, mapping, quality)
  polygon_file <- file.path(patch_dir, paste0(stem, ".shp"))
  lookup_file <- file.path(patch_dir, paste0(spec$lookup_prefix, stem, ".csv"))
  area_file <- file.path(patch_dir, paste0(spec$area_prefix, stem, ".csv"))

  missing <- c(polygon_file, lookup_file, area_file)[
    !file.exists(c(polygon_file, lookup_file, area_file))
  ]
  if (length(missing)) {
    stop(
      "Missing files for ", stem, " (", spec$label, "): ",
      paste(missing, collapse = "; "),
      call. = FALSE
    )
  }

  polygons <- suppressWarnings(sf::st_read(polygon_file, quiet = TRUE))
  if (!nrow(polygons)) stop("Empty polygon file: ", polygon_file, call. = FALSE)
  if (is.na(sf::st_crs(polygons))) {
    stop("Polygon file has no CRS: ", polygon_file, call. = FALSE)
  }
  polygons <- sf::st_make_valid(polygons)
  polygons <- sf::st_transform(polygons, analysis_crs)
  polygons$polygon_id <- seq_len(nrow(polygons))

  lookup <- readr::read_csv(lookup_file, show_col_types = FALSE) |>
    dplyr::transmute(
      polygon_id = as.integer(.data$polygon_id),
      final_id = as.character(.data$final_id)
    )
  areas_raw <- readr::read_csv(area_file, show_col_types = FALSE)
  has_n_polygons <- "n_polygons" %in% names(areas_raw)
  areas <- areas_raw |>
    dplyr::transmute(
      final_id = as.character(.data$final_id),
      area_sq_m_file = as.numeric(.data$area_sq_m),
      n_polygons_file = if (has_n_polygons) {
        as.integer(.data$n_polygons)
      } else {
        NA_integer_
      }
    )

  if (anyNA(lookup$polygon_id) || anyNA(lookup$final_id)) {
    stop("Lookup contains missing polygon_id or final_id values: ", lookup_file, call. = FALSE)
  }
  if (anyDuplicated(lookup$polygon_id)) {
    stop("Lookup contains duplicated polygon_id values: ", lookup_file, call. = FALSE)
  }
  if (anyNA(areas$final_id) || anyDuplicated(areas$final_id)) {
    stop("Area table contains missing or duplicated final_id values: ", area_file, call. = FALSE)
  }

  missing_lookup <- setdiff(polygons$polygon_id, lookup$polygon_id)
  if (length(missing_lookup)) {
    stop(
      "Lookup does not cover every source polygon in ", stem,
      ". Missing polygon IDs include: ",
      paste(utils::head(missing_lookup, 8L), collapse = ", "),
      call. = FALSE
    )
  }
  unexpected_lookup <- setdiff(lookup$polygon_id, polygons$polygon_id)
  if (length(unexpected_lookup)) {
    stop(
      "Lookup contains polygon IDs absent from the shapefile in ", stem,
      ". Unexpected IDs include: ",
      paste(utils::head(unexpected_lookup, 8L), collapse = ", "),
      call. = FALSE
    )
  }

  final_polygons <- polygons |>
    dplyr::select(.data$polygon_id) |>
    dplyr::left_join(lookup, by = "polygon_id") |>
    dplyr::group_by(.data$final_id) |>
    dplyr::summarise(n_source_polygons = dplyr::n(), .groups = "drop") |>
    dplyr::left_join(areas, by = "final_id")

  area_sq_m_geometry <- as.numeric(sf::st_area(final_polygons))
  perimeter_m <- as.numeric(sf::st_length(sf::st_boundary(final_polygons)))
  compactness <- 4 * pi * area_sq_m_geometry / (perimeter_m^2)

  point_surface <- suppressWarnings(sf::st_point_on_surface(final_polygons))
  centroid <- suppressWarnings(sf::st_centroid(final_polygons))
  point_xy <- sf::st_coordinates(point_surface)
  centroid_xy <- sf::st_coordinates(centroid)

  final_polygons$species_id <- species_id
  final_polygons$mapping <- mapping
  final_polygons$quality <- quality
  final_polygons$scenario <- paste(mapping, quality, sep = "_")
  final_polygons$area_sq_m_geometry <- area_sq_m_geometry
  final_polygons$area_sq_m <- ifelse(
    is.finite(final_polygons$area_sq_m_file),
    final_polygons$area_sq_m_file,
    area_sq_m_geometry
  )
  final_polygons$area_relative_error <- abs(
    final_polygons$area_sq_m_file - area_sq_m_geometry
  ) / pmax(area_sq_m_geometry, 1)
  final_polygons$area_km2 <- final_polygons$area_sq_m / 1e6
  final_polygons$perimeter_km <- perimeter_m / 1000
  final_polygons$compactness <- compactness
  final_polygons$point_X_km <- point_xy[, 1L] / 1000
  final_polygons$point_Y_km <- point_xy[, 2L] / 1000
  final_polygons$centroid_X_km <- centroid_xy[, 1L] / 1000
  final_polygons$centroid_Y_km <- centroid_xy[, 2L] / 1000
  final_polygons$centroid_to_surface_km <- as.numeric(
    sf::st_distance(centroid, point_surface, by_element = TRUE)
  ) / 1000
  final_polygons$source_polygon_file <- polygon_file
  final_polygons$source_lookup_file <- lookup_file
  final_polygons$source_area_file <- area_file
  final_polygons
}

assemble_spatial_analysis_data <- function(
    scores,
    patch_dir,
    merge_variant = c("zero", "10m", "20m"),
    analysis_crs = 25832,
    strict = TRUE) {
  merge_variant <- match.arg(merge_variant)
  combinations <- scores |>
    dplyr::distinct(.data$species_id, .data$mapping, .data$quality) |>
    dplyr::arrange(.data$species_id, .data$mapping, .data$quality)

  geometries <- lapply(seq_len(nrow(combinations)), function(i) {
    read_final_patch_geometry(
      patch_dir = patch_dir,
      species_id = combinations$species_id[[i]],
      mapping = combinations$mapping[[i]],
      quality = combinations$quality[[i]],
      merge_variant = merge_variant,
      analysis_crs = analysis_crs
    )
  })
  geometry <- do.call(rbind, geometries)

  join_key <- c("species_id", "mapping", "quality", "scenario", "final_id")
  missing_geometry <- dplyr::anti_join(
    scores,
    sf::st_drop_geometry(geometry),
    by = join_key
  )
  if (strict && nrow(missing_geometry)) {
    examples <- missing_geometry |>
      dplyr::select(dplyr::all_of(join_key)) |>
      utils::head(8L)
    stop(
      "FPCA IDs do not match the selected geometry/area variant. ",
      "This usually means that FPCA was run on a different 0 m/10 m/20 m correction. ",
      "Examples:\n", paste(utils::capture.output(print(examples)), collapse = "\n"),
      call. = FALSE
    )
  }

  analysis_sf <- geometry |>
    dplyr::inner_join(scores, by = join_key)

  if (!nrow(analysis_sf)) {
    stop("No FPCA rows matched the final patch geometries.", call. = FALSE)
  }
  analysis_sf
}

prepare_model_data <- function(analysis_sf) {
  dat <- sf::st_drop_geometry(analysis_sf)
  dat$mapping <- stats::relevel(factor(dat$mapping), ref = "broad")
  dat$quality <- factor(dat$quality, levels = c("High", "Medium", "Low"))
  dat$species <- factor(dat$species)
  dat$scenario <- factor(
    dat$scenario,
    levels = c(
      "broad_High", "broad_Medium", "broad_Low",
      "narrow_High", "narrow_Medium", "narrow_Low"
    )
  )
  if (any(!is.finite(dat$area_sq_m)) || any(dat$area_sq_m <= 0)) {
    stop("Patch areas must be positive and finite before log transformation.", call. = FALSE)
  }
  if (!is.finite(stats::sd(dat$FPCA1)) || stats::sd(dat$FPCA1) == 0) {
    stop("FPCA1 has no finite variation and cannot be standardized.", call. = FALSE)
  }
  dat$log_area <- log(dat$area_sq_m)
  if (!is.finite(stats::sd(dat$log_area)) || stats::sd(dat$log_area) == 0) {
    stop("Log patch area has no finite variation and cannot be standardized.", call. = FALSE)
  }
  dat$log_area_z <- as.numeric(scale(dat$log_area))
  dat$FPCA1_z <- as.numeric(scale(dat$FPCA1))

  required <- c(
    "FPCA1_z", "log_area_z", "point_X_km", "point_Y_km",
    "centroid_X_km", "centroid_Y_km", "species", "mapping", "quality"
  )
  keep <- stats::complete.cases(dat[, required, drop = FALSE])
  if (any(!keep)) {
    warning(sum(!keep), " incomplete rows were omitted from model data.")
    dat <- dat[keep, , drop = FALSE]
  }
  if (nrow(dat) < 20L) stop("Too few complete patch observations.", call. = FALSE)
  dat
}

geometry_support_summary <- function(model_data) {
  probs <- c(0, 0.5, 0.75, 0.9, 0.95, 0.99, 1)
  variables <- c(
    "area_km2", "compactness", "centroid_to_surface_km",
    "area_relative_error"
  )
  rows <- lapply(variables, function(variable) {
    values <- model_data[[variable]]
    qs <- stats::quantile(values, probs = probs, na.rm = TRUE, names = FALSE)
    data.frame(
      variable = variable,
      quantile = paste0(probs * 100, "%"),
      value = as.numeric(qs),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

assign_spatial_cells <- function(data, xy_cols, grid_km) {
  if (length(xy_cols) != 2L || !all(xy_cols %in% names(data))) {
    stop("xy_cols must name two coordinate columns.", call. = FALSE)
  }
  if (!is.numeric(grid_km) || length(grid_km) != 1L || grid_km <= 0) {
    stop("grid_km must be one positive number.", call. = FALSE)
  }
  x_index <- floor(data[[xy_cols[[1L]]]] / grid_km)
  y_index <- floor(data[[xy_cols[[2L]]]] / grid_km)
  paste(x_index, y_index, sep = ":")
}

select_mem_block <- function(
    data,
    xy_cols,
    grid_km = 10,
    ecological_formula = FPCA1_z ~ log_area_z + species + mapping + quality,
    method = c("MIR", "FWD"),
    nperm = 999,
    nperm_global = 9999) {
  method <- match.arg(method)
  ecological_fit <- stats::lm(ecological_formula, data = data)
  residual_value <- stats::residuals(ecological_fit)
  cell_id <- assign_spatial_cells(data, xy_cols = xy_cols, grid_km = grid_km)

  cell_data <- data.frame(
    cell_id = cell_id,
    residual = residual_value,
    X = data[[xy_cols[[1L]]]],
    Y = data[[xy_cols[[2L]]]],
    stringsAsFactors = FALSE
  ) |>
    dplyr::group_by(.data$cell_id) |>
    dplyr::summarise(
      residual = mean(.data$residual),
      X = mean(.data$X),
      Y = mean(.data$Y),
      n_patches = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$cell_id)

  if (nrow(cell_data) < 10L) {
    stop("Fewer than 10 occupied spatial cells; dbMEM is not informative.", call. = FALSE)
  }

  mem_all <- adespatial::dbmem(
    as.matrix(cell_data[, c("X", "Y")]),
    MEM.autocor = "positive",
    store.listw = TRUE,
    silent = TRUE
  )
  listw <- attr(mem_all, "listw")
  selection <- adespatial::mem.select(
    x = cell_data$residual,
    listw = listw,
    method = method,
    MEM.autocor = "positive",
    MEM.all = TRUE,
    nperm = nperm,
    nperm.global = nperm_global,
    verbose = FALSE
  )

  selected <- selection$MEM.select
  if (is.null(selected)) {
    selected <- matrix(numeric(0), nrow = nrow(cell_data), ncol = 0L)
  } else {
    selected <- as.matrix(selected)
    if (is.null(dim(selected))) selected <- matrix(selected, ncol = 1L)
    colnames(selected) <- paste0("MEM", seq_len(ncol(selected)))
  }

  observation_mem <- selected[match(cell_id, cell_data$cell_id), , drop = FALSE]
  rownames(observation_mem) <- NULL
  list(
    matrix = observation_mem,
    selected_at_cells = selected,
    cells = cell_data,
    cell_id = cell_id,
    all_mem_count = ncol(as.matrix(mem_all)),
    selected_mem_count = ncol(selected),
    selection = selection,
    ecological_fit = ecological_fit,
    xy_cols = xy_cols,
    grid_km = grid_km,
    method = method
  )
}

adjusted_r2 <- function(model) {
  value <- vegan::RsquareAdj(model)$adj.r.squared
  if (length(value)) as.numeric(value) else NA_real_
}

run_variance_partition <- function(data, mem_block) {
  if (nrow(mem_block$matrix) != nrow(data)) {
    stop("MEM rows do not match the model data.", call. = FALSE)
  }
  response <- matrix(data$FPCA1_z, ncol = 1L)
  colnames(response) <- "FPCA1_z"
  area <- data.frame(log_area_z = data$log_area_z)
  species <- as.data.frame(
    stats::model.matrix(~ species, data = data)[, -1L, drop = FALSE]
  )
  habitat <- as.data.frame(stats::model.matrix(~ mapping + quality, data = data)[, -1L, drop = FALSE])
  spatial <- as.data.frame(mem_block$matrix)

  blocks <- list(Area = area, Species = species, Habitat = habitat)
  if (ncol(spatial)) blocks$Spatial <- spatial
  combined <- do.call(cbind, blocks)
  full_fit <- vegan::rda(response, combined)
  full_adjusted_r2 <- adjusted_r2(full_fit)

  table_rows <- lapply(names(blocks), function(block_name) {
    target <- blocks[[block_name]]
    other_names <- setdiff(names(blocks), block_name)
    others <- if (length(other_names)) {
      do.call(cbind, blocks[other_names])
    } else {
      NULL
    }
    marginal_fit <- vegan::rda(response, target)
    unique_fit <- if (is.null(others)) {
      marginal_fit
    } else {
      vegan::rda(response, target, others)
    }
    data.frame(
      block = block_name,
      marginal_adjusted_r2 = adjusted_r2(marginal_fit),
      unique_adjusted_r2 = adjusted_r2(unique_fit),
      stringsAsFactors = FALSE
    )
  })
  partition_table <- dplyr::bind_rows(table_rows)
  if (!"Spatial" %in% partition_table$block) {
    partition_table <- dplyr::bind_rows(
      partition_table,
      data.frame(
        block = "Spatial",
        marginal_adjusted_r2 = 0,
        unique_adjusted_r2 = 0,
        stringsAsFactors = FALSE
      )
    )
  }
  partition_table$full_model_adjusted_r2 <- full_adjusted_r2

  varpart <- switch(
    as.character(length(blocks)),
    `3` = vegan::varpart(response, blocks[[1L]], blocks[[2L]], blocks[[3L]]),
    `4` = vegan::varpart(
      response,
      blocks[[1L]], blocks[[2L]], blocks[[3L]], blocks[[4L]]
    ),
    stop("Variance partitioning requires three or four blocks.", call. = FALSE)
  )
  list(
    varpart = varpart,
    table = partition_table,
    full_fit = full_fit,
    blocks = blocks,
    response = response
  )
}

varpart_fraction_table <- function(partition, support) {
  fractions <- as.data.frame(partition$part$indfract)
  if (!nrow(fractions)) {
    return(data.frame())
  }
  fractions$fraction <- rownames(fractions)
  rownames(fractions) <- NULL
  fractions$support <- support
  fractions |>
    dplyr::relocate(.data$support, .data$fraction)
}

fit_spde_suite <- function(
    data,
    xy_cols = c("point_X_km", "point_Y_km"),
    cutoffs_km = c(10, 20, 40),
    formula = FPCA1_z ~ log_area_z + mapping + quality + (1 | species)) {
  cutoffs_km <- sort(unique(as.numeric(cutoffs_km)))
  if (any(!is.finite(cutoffs_km)) || any(cutoffs_km <= 0)) {
    stop("Mesh cutoffs must be positive finite numbers.", call. = FALSE)
  }

  nonspatial <- sdmTMB::sdmTMB(
    formula = formula,
    data = data,
    family = stats::gaussian(),
    spatial = "off"
  )
  meshes <- lapply(cutoffs_km, function(cutoff) {
    sdmTMB::make_mesh(data, xy_cols = xy_cols, cutoff = cutoff)
  })
  spatial <- Map(function(mesh, cutoff) {
    sdmTMB::sdmTMB(
      formula = formula,
      data = data,
      mesh = mesh,
      family = stats::gaussian(),
      spatial = "on"
    )
  }, meshes, cutoffs_km)
  names(meshes) <- paste0("cutoff_", cutoffs_km, "km")
  names(spatial) <- names(meshes)
  list(
    nonspatial = nonspatial,
    spatial = spatial,
    meshes = meshes,
    cutoffs_km = cutoffs_km,
    xy_cols = xy_cols,
    formula = formula
  )
}

mesh_vertex_count <- function(mesh) {
  candidates <- list(
    try(mesh$mesh$loc, silent = TRUE),
    try(mesh$mesh$loc[, 1:2, drop = FALSE], silent = TRUE),
    try(mesh$loc, silent = TRUE)
  )
  for (candidate in candidates) {
    if (!inherits(candidate, "try-error") && !is.null(candidate)) {
      n <- nrow(candidate)
      if (length(n) && is.finite(n)) return(as.integer(n))
    }
  }
  NA_integer_
}

tidy_spde_suite <- function(suite, confidence = 0.95) {
  fixed <- dplyr::bind_rows(
    dplyr::mutate(
      as.data.frame(sdmTMB::tidy(suite$nonspatial, conf.int = TRUE, conf.level = confidence)),
      model = "nonspatial",
      cutoff_km = NA_real_
    ),
    dplyr::bind_rows(lapply(seq_along(suite$spatial), function(i) {
      dplyr::mutate(
        as.data.frame(sdmTMB::tidy(
          suite$spatial[[i]], conf.int = TRUE, conf.level = confidence
        )),
        model = "SPDE",
        cutoff_km = suite$cutoffs_km[[i]]
      )
    }))
  )

  random_parameters <- dplyr::bind_rows(lapply(seq_along(suite$spatial), function(i) {
    dplyr::mutate(
      as.data.frame(sdmTMB::tidy(
        suite$spatial[[i]], effects = "ran_pars", conf.int = TRUE,
        conf.level = confidence
      )),
      model = "SPDE",
      cutoff_km = suite$cutoffs_km[[i]]
    )
  }))

  aic <- dplyr::bind_rows(
    data.frame(
      model = "nonspatial",
      cutoff_km = NA_real_,
      AIC = stats::AIC(suite$nonspatial),
      mesh_vertices = NA_integer_
    ),
    dplyr::bind_rows(lapply(seq_along(suite$spatial), function(i) {
      data.frame(
        model = "SPDE",
        cutoff_km = suite$cutoffs_km[[i]],
        AIC = stats::AIC(suite$spatial[[i]]),
        mesh_vertices = mesh_vertex_count(suite$meshes[[i]])
      )
    }))
  )
  aic$delta_AIC <- aic$AIC - min(aic$AIC, na.rm = TRUE)
  list(fixed = fixed, random_parameters = random_parameters, aic = aic)
}

compare_fixed_effects <- function(tidy_fixed, primary_cutoff_km) {
  nonspatial <- tidy_fixed |>
    dplyr::filter(.data$model == "nonspatial") |>
    dplyr::select(
      .data$term,
      nonspatial_estimate = .data$estimate,
      nonspatial_se = .data$std.error,
      nonspatial_low = .data$conf.low,
      nonspatial_high = .data$conf.high
    )
  spatial <- tidy_fixed |>
    dplyr::filter(
      .data$model == "SPDE",
      .data$cutoff_km == primary_cutoff_km
    ) |>
    dplyr::select(
      .data$term,
      spatial_estimate = .data$estimate,
      spatial_se = .data$std.error,
      spatial_low = .data$conf.low,
      spatial_high = .data$conf.high
    )
  dplyr::inner_join(nonspatial, spatial, by = "term") |>
    dplyr::mutate(
      absolute_change = .data$spatial_estimate - .data$nonspatial_estimate,
      proportional_change = dplyr::if_else(
        abs(.data$nonspatial_estimate) > 1e-8,
        .data$absolute_change / abs(.data$nonspatial_estimate),
        NA_real_
      ),
      same_sign = sign(.data$nonspatial_estimate) == sign(.data$spatial_estimate)
    )
}

make_dharma_residuals <- function(model, nsim = 500, seed = 37) {
  set.seed(seed)
  simulations <- stats::simulate(model, nsim = nsim, type = "mle-mvn")
  sdmTMB::dharma_residuals(
    simulations,
    model,
    return_DHARMa = TRUE
  )
}

dharma_spatial_test_from_residuals <- function(
    residuals,
    data,
    xy_cols,
    grid_km = 5,
    seed = 37,
    nsim = NA_integer_) {
  cell_id <- assign_spatial_cells(data, xy_cols = xy_cols, grid_km = grid_km)
  cell_factor <- factor(cell_id, levels = sort(unique(cell_id)))
  grouped <- DHARMa::recalculateResiduals(
    residuals,
    group = cell_factor,
    seed = seed
  )
  locations <- data.frame(
    cell_id = cell_factor,
    X = data[[xy_cols[[1L]]]],
    Y = data[[xy_cols[[2L]]]],
    stringsAsFactors = FALSE
  ) |>
    dplyr::group_by(.data$cell_id) |>
    dplyr::summarise(X = mean(.data$X), Y = mean(.data$Y), .groups = "drop") |>
    dplyr::arrange(.data$cell_id)

  test <- DHARMa::testSpatialAutocorrelation(
    grouped,
    x = locations$X,
    y = locations$Y,
    plot = FALSE
  )
  estimates <- test$estimate
  observed <- if ("observed" %in% names(estimates)) {
    unname(estimates[["observed"]])
  } else {
    unname(estimates[[1L]])
  }
  expected <- if ("expected" %in% names(estimates)) {
    unname(estimates[["expected"]])
  } else {
    NA_real_
  }
  result_table <- data.frame(
    moran_observed = observed,
    moran_expected = expected,
    p_value = test$p.value,
    n_spatial_cells = nrow(locations),
    grid_km = grid_km,
    nsim = nsim,
    stringsAsFactors = FALSE
  )
  list(
    table = result_table,
    test = test,
    grouped_residuals = grouped,
    locations = locations
  )
}

dharma_spatial_test <- function(
    model,
    data,
    xy_cols,
    grid_km = 5,
    nsim = 500,
    seed = 37) {
  residuals <- make_dharma_residuals(model, nsim = nsim, seed = seed)
  dharma_spatial_test_from_residuals(
    residuals = residuals,
    data = data,
    xy_cols = xy_cols,
    grid_km = grid_km,
    seed = seed,
    nsim = nsim
  )
}

spatial_field_at_observations <- function(model, data, grid_km = 5) {
  prediction <- as.data.frame(stats::predict(model))
  if (!"omega_s" %in% names(prediction)) {
    stop("The fitted model did not return an omega_s spatial field.", call. = FALSE)
  }
  data.frame(
    X = data$point_X_km,
    Y = data$point_Y_km,
    omega_s = prediction$omega_s,
    stringsAsFactors = FALSE
  ) |>
    dplyr::mutate(
      grid_x = floor(.data$X / grid_km) * grid_km + grid_km / 2,
      grid_y = floor(.data$Y / grid_km) * grid_km + grid_km / 2
    ) |>
    dplyr::group_by(.data$grid_x, .data$grid_y) |>
    dplyr::summarise(omega_s = mean(.data$omega_s), .groups = "drop")
}
