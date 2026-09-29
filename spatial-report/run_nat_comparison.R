# From the ButterflyHabitats project root:
# source("spatial-report/run_nat_comparison.R")
# render_nat_comparison(project_root = getwd())
# Sourcing only defines the entry point; it never starts model fitting.

.nat_report_directory <- local({
  files <- vapply(sys.frames(), function(frame) {
    if (is.null(frame$ofile)) "" else as.character(frame$ofile)[1L]
  }, character(1))
  files <- files[nzchar(files)]
  if (length(files)) dirname(normalizePath(tail(files, 1L), winslash = "/", mustWork = TRUE)) else NULL
})

render_nat_comparison <- function(
    project_root = getwd(),
    prepared_data = "Results/spatial_autocorrelation_10m/spatial_model_data.rds",
    previous_results_dir = NULL,
    output_dir = NULL,
    run_residuals = TRUE,
    report_dir = .nat_report_directory,
    quiet = FALSE) {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  resolve <- function(path) {
    if (!grepl("^(/|[A-Za-z]:[/\\\\])", path)) path <- file.path(project_root, path)
    normalizePath(path, winslash = "/", mustWork = FALSE)
  }
  if (is.null(report_dir)) report_dir <- file.path(project_root, "spatial-report")
  report_dir <- resolve(report_dir)
  needed <- c("05_nat_model_comparison.Rmd", "nat_comparison_helpers.R",
               "spatial_analysis_helpers.R", "spatial_references.bib")
  if (!all(file.exists(file.path(report_dir, needed)))) {
    stop("Use the complete updated spatial-report folder; required files are missing.")
  }
  env <- new.env(parent = globalenv())
  sys.source(file.path(report_dir, "spatial_analysis_helpers.R"), envir = env)
  sys.source(file.path(report_dir, "nat_comparison_helpers.R"), envir = env)
  env$assert_spatial_packages(c("rmarkdown", "bookdown", "digest",
                                env$required_spatial_packages()))
  prepared_data <- resolve(prepared_data)
  if (!file.exists(prepared_data)) stop("Prepared data file not found: ", prepared_data)
  message("Loading the saved model table once; no polygon preparation.")
  saved <- readRDS(prepared_data)
  scientific <- c("merge_variant", "analysis_crs", "mem_grid_km", "mem_method", "mem_nperm",
                   "mem_nperm_global", "mesh_cutoffs_km", "primary_cutoff_km", "residual_grid_km",
                   "residual_nsim", "run_centroid_sensitivity", "seed")
  if (!is.list(saved$parameters) || !all(scientific %in% names(saved$parameters))) {
    stop("Prepared RDS is missing the analysis settings needed for this comparison.")
  }
  params <- saved$parameters[scientific]
  for (name in c("mesh_cutoffs_km", "residual_grid_km")) {
    params[[name]] <- as.numeric(unlist(params[[name]]))
  }
  if (is.null(output_dir)) output_dir <- file.path("Results", paste0("nat_spatial_comparison_", params$merge_variant))
  output_dir <- resolve(output_dir)
  if (is.null(previous_results_dir)) {
    candidates <- c(dirname(prepared_data), file.path(list.dirs(
      file.path(project_root, "spatial-report"), recursive = FALSE), "results"))
    candidates <- unique(candidates[file.exists(file.path(candidates, "spde_point_on_surface_models.rds"))])
    if (length(candidates) > 1L) {
      stop("More than one previous model directory found. Set previous_results_dir explicitly: ",
           paste(candidates, collapse = "; "))
    }
    previous_results_dir <- if (length(candidates)) candidates[[1L]] else ""
  } else if (nzchar(previous_results_dir)) {
    previous_results_dir <- resolve(previous_results_dir)
    if (!file.exists(file.path(previous_results_dir, "spde_point_on_surface_models.rds"))) {
      stop("The specified previous_results_dir has no saved point-on-surface model suite.")
    }
  }
  params$project_root <- project_root
  params$prepared_data <- prepared_data
  params$previous_results_dir <- previous_results_dir
  params$comparison_output_dir <- output_dir
  params$coordinate_crs <- 4326
  params$run_residuals <- isTRUE(run_residuals)
  if (!params$primary_cutoff_km %in% params$mesh_cutoffs_km) stop("Primary cutoff is absent from mesh_cutoffs_km.")
  env$.nat_prepared <- env$nat_read_prepared(saved, params$merge_variant, params$analysis_crs)
  rm(saved)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(params, file.path(output_dir, "comparison_parameters.rds"))
  message("Prepared observations: ", format(nrow(env$.nat_prepared$data), big.mark = ","))
  message("Previous fits: ", if (nzchar(previous_results_dir)) previous_results_dir else "none; models will be fitted")
  message("Output and checkpoints: ", output_dir)
  rmarkdown::render(
    file.path(report_dir, "05_nat_model_comparison.Rmd"),
    output_file = paste0("patchFPCA_Nat_comparison_", params$merge_variant, ".pdf"),
    output_dir = output_dir, knit_root_dir = report_dir,
    params = params, envir = env, quiet = quiet
  )
}
