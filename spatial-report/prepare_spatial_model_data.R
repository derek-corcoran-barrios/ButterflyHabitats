# Prepare the geometry-free model table once, with one resumable checkpoint per
# species/scenario. Source this from ButterflyHabitats; it never fits models.

.spatial_preparation_dir <- local({
  files <- vapply(sys.frames(), function(frame) {
    if (is.null(frame$ofile)) "" else as.character(frame$ofile)[1L]
  }, character(1))
  files <- files[nzchar(files)]
  if (length(files)) dirname(normalizePath(tail(files, 1L), winslash = "/", mustWork = TRUE)) else NULL
})

prepare_spatial_model_data <- function(
    project_root = getwd(),
    fpca_results_dir = "Results/zero",
    patch_dir = "Species_PatchDistances",
    spatial_output_dir = NULL,
    merge_variant = c("zero", "10m", "20m"),
    expected_scenarios = 42L,
    report_dir = .spatial_preparation_dir) {
  merge_variant <- match.arg(merge_variant)
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  resolve <- function(path) {
    if (!grepl("^(/|[A-Za-z]:[/\\\\])", path)) path <- file.path(project_root, path)
    normalizePath(path, winslash = "/", mustWork = FALSE)
  }
  if (is.null(report_dir)) report_dir <- file.path(project_root, "spatial-report")
  report_dir <- resolve(report_dir)
  if (is.null(spatial_output_dir)) {
    spatial_output_dir <- file.path("Results", paste0("spatial_autocorrelation_", merge_variant))
  }
  fpca_results_dir <- resolve(fpca_results_dir)
  patch_dir <- resolve(patch_dir)
  spatial_output_dir <- resolve(spatial_output_dir)
  fpca_file <- file.path(fpca_results_dir, "patch_fpca_results.rds")
  if (!file.exists(fpca_file)) {
    stop("Missing 0 m FPCA results (or selected variant): ", fpca_file,
         ". Run the matching distance-file reorder and FPCA first.", call. = FALSE)
  }
  if (!dir.exists(patch_dir)) stop("Missing patch directory: ", patch_dir, call. = FALSE)
  required <- c("04_spatial_autocorrelation.Rmd", "spatial_analysis_helpers.R",
                "nat_comparison_helpers.R")
  if (!all(file.exists(file.path(report_dir, required)))) {
    stop("Use the updated spatial-report folder; required files are missing.", call. = FALSE)
  }

  # Use precisely the report's scientific defaults so the resulting RDS is
  # accepted by render_nat_comparison(), including list-valued YAML settings.
  defaults <- rmarkdown::yaml_front_matter(
    file.path(report_dir, "04_spatial_autocorrelation.Rmd"))$params
  if (!is.list(defaults) || !all(c("analysis_crs", "mem_grid_km", "mesh_cutoffs_km",
      "primary_cutoff_km", "residual_grid_km", "residual_nsim", "seed") %in% names(defaults))) {
    stop("The spatial report has incomplete YAML analysis settings.", call. = FALSE)
  }
  params <- defaults
  params$project_root <- project_root
  params$fpca_results_dir <- fpca_results_dir
  params$patch_dir <- patch_dir
  params$spatial_output_dir <- spatial_output_dir
  params$merge_variant <- merge_variant

  e <- new.env(parent = globalenv())
  sys.source(file.path(report_dir, "spatial_analysis_helpers.R"), envir = e)
  sys.source(file.path(report_dir, "nat_comparison_helpers.R"), envir = e)
  e$assert_spatial_packages(c("digest", "rmarkdown", "sf", "dplyr", "readr"))
  dir.create(spatial_output_dir, recursive = TRUE, showWarnings = FALSE)
  final_file <- file.path(spatial_output_dir, "spatial_model_data.rds")
  if (file.exists(final_file)) {
    stop("A completed model table already exists at ", final_file,
         ". Specify a new spatial_output_dir to start another preparation.", call. = FALSE)
  }

  e$nat_log(spatial_output_dir, "read_fpca_patch_scores", "START")
  scores <- e$read_fpca_patch_scores(fpca_results_dir)
  e$nat_log(spatial_output_dir, "read_fpca_patch_scores", "DONE")
  combinations <- dplyr::distinct(scores, .data$species_id, .data$mapping, .data$quality)
  combinations <- dplyr::arrange(combinations, .data$species_id, .data$mapping, .data$quality)
  spec <- e$spatial_variant_spec(merge_variant)
  stems <- paste(combinations$species_id, combinations$mapping, combinations$quality, sep = "_")
  if (!is.null(expected_scenarios) && length(stems) != expected_scenarios) {
    stop("Expected ", expected_scenarios, " species/scenarios but found ",
         length(stems), ". Check the selected FPCA result file before geometry work.",
         call. = FALSE)
  }
  inputs <- lapply(stems, function(stem) {
    polygon <- file.path(patch_dir, paste0(stem, ".shp"))
    c(polygon, sub("\\.shp$", ".dbf", polygon),
      sub("\\.shp$", ".shx", polygon), sub("\\.shp$", ".prj", polygon),
      file.path(patch_dir, paste0(spec$lookup_prefix, stem, ".csv")),
      file.path(patch_dir, paste0(spec$area_prefix, stem, ".csv")))
  })
  missing <- unique(unlist(inputs)[!file.exists(unlist(inputs))])
  if (length(missing)) {
    stop("Missing geometry/lookup/area inputs; first examples: ",
         paste(utils::head(missing, 10L), collapse = "; "), call. = FALSE)
  }
  e$nat_log(spatial_output_dir, "preflight", paste("DONE", length(stems), "scenarios"))

  join_key <- c("species_id", "mapping", "quality", "scenario", "final_id")
  chunk_paths <- character(length(stems))
  for (i in seq_along(stems)) {
    group_scores <- scores[scores$species_id == combinations$species_id[[i]] &
      scores$mapping == combinations$mapping[[i]] &
      scores$quality == combinations$quality[[i]], , drop = FALSE]
    files <- inputs[[i]]
    info <- file.info(files)
    signature <- data.frame(file = normalizePath(files, winslash = "/", mustWork = TRUE),
      size = info$size, modified = as.numeric(info$mtime))
    key <- list(variant = merge_variant, crs = params$analysis_crs,
      score_hash = e$nat_hash(group_scores), source_files = signature,
      helper_code = e$nat_function_key(c("read_final_patch_geometry", "spatial_variant_spec",
        "scenario_file_stem")), packages = e$nat_versions(c("sf", "dplyr", "readr")))
    stage <- paste0("geometry_", stems[[i]])
    chunk <- e$nat_checkpoint(spatial_output_dir, stage, key, function() {
      polygon <- e$read_final_patch_geometry(patch_dir,
        combinations$species_id[[i]], combinations$mapping[[i]],
        combinations$quality[[i]], merge_variant, params$analysis_crs)
      missing_scores <- dplyr::anti_join(group_scores, sf::st_drop_geometry(polygon), by = join_key)
      if (nrow(missing_scores)) {
        stop("FPCA patch IDs absent from this ", merge_variant, " geometry: ",
             stems[[i]], ". First ID: ", missing_scores$final_id[[1L]])
      }
      joined <- dplyr::inner_join(polygon, group_scores, by = join_key)
      if (nrow(joined) != nrow(group_scores)) {
        stop("Patch ID join changed the number of scored observations for ", stems[[i]])
      }
      sf::st_drop_geometry(joined)
    })
    chunk_paths[[i]] <- e$nat_checkpoint_path(spatial_output_dir, stage, key)
    rm(chunk, group_scores)
  }
  rm(scores)
  e$nat_log(spatial_output_dir, "combine_model_data", "START")
  chunks <- lapply(chunk_paths, function(path) readRDS(path)$value)
  model_data <- e$prepare_model_data(dplyr::bind_rows(chunks))
  rm(chunks)
  # Validate the final table before exposing it to the comparison report.
  payload <- list(model_data = model_data, parameters = params, generated = Sys.time())
  e$nat_read_prepared(payload, merge_variant, params$analysis_crs)
  temporary <- tempfile("pending_spatial_data_", tmpdir = spatial_output_dir)
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(payload, temporary, compress = FALSE)
  if (file.exists(final_file) || !file.rename(temporary, final_file)) {
    stop("Could not commit the prepared model table: ", final_file, call. = FALSE)
  }
  e$nat_log(spatial_output_dir, "combine_model_data", paste("DONE", nrow(model_data), "rows"))
  invisible(final_file)
}
