# Spatial reports

`05_nat_model_comparison.Rmd` adds Nat's area transformation and coordinate
interaction to the comparison using the completed, geometry-free model table.
It produces a separate bookdown PDF with `spatial_references.bib`, CSV tables,
a progress log, convergence logs, and resumable RDS checkpoints.

## First run on the unbuffered (0 m) patch correction

The published 10 m report uses different patch boundaries and FPCA scores from
the unbuffered manuscript analysis. Before generating new FPCA scores, look for
an existing result file and confirm which patch correction produced it:

```r
list.files("Results", pattern = "^patch_fpca_results\\.rds$",
  recursive = TRUE, full.names = TRUE)
zero_fpca_dir <- "Results/zero"  # Change only to a verified 0 m result directory.
file.exists(file.path(zero_fpca_dir, "patch_fpca_results.rds"))
```

If it does not, construct it **once** from the zero-buffer distance files.
Their filename has no `_10m` or `_20m` suffix. Keep the reordered data and FPCA
results in their own variant-specific directories:

```r
library(patchFPCA)
patch_dir <- "Species_PatchDistances"
zero_files <- list.files(patch_dir,
  pattern = "_distances_corrected_superpolygons\\.rds$", full.names = TRUE)
stopifnot(length(zero_files) > 0L)

if (!file.exists(file.path(zero_fpca_dir, "patch_fpca_results.rds"))) {
  patchFPCA::reorder_distance_files(
    input_dir = patch_dir, output_dir = "Reordered_zero",
    pattern = "_distances_corrected_superpolygons\\.rds$",
    min_neighbors = 5L
  )
  zero_reordered <- patchFPCA::read_reordered_data("Reordered_zero")
  zero_fpca <- patchFPCA::run_all_fpca(zero_reordered$data,
    k_max = 5L, seed = 37L, center = FALSE,
    scale. = FALSE, log_transform = TRUE)
  patchFPCA::save_fpca_results(zero_fpca, zero_fpca_dir)
}
```

`prepare_spatial_model_data.R` uses the existing patch/report helpers but saves
each species/scenario geometry as an RDS checkpoint immediately. It validates
the source files and FPCA patch IDs and writes the final geometry-free table
only after all joins and global response/area scaling succeed. If it stops,
run the same command again; completed scenario joins are loaded, including the
very large groups. This step can still take hours on the network drive.

```r
source("spatial-report/prepare_spatial_model_data.R")
zero_data <- "Results/spatial_autocorrelation_zero/spatial_model_data.rds"
if (!file.exists(zero_data)) {
  prepare_spatial_model_data(
    project_root = getwd(), fpca_results_dir = zero_fpca_dir,
    patch_dir = "Species_PatchDistances", merge_variant = "zero"
  )
}
```

Then run the Nat comparison using the matching input. The zero results have
their own output directory. Specify an empty previous-fit directory so the
10 m fitted models are never imported. This initially omits residual simulations
to show the RDA and mixed-model comparison sooner:

```r
source("spatial-report/run_nat_comparison.R")
render_nat_comparison(
  project_root = getwd(), prepared_data = zero_data,
  previous_results_dir = "", run_residuals = FALSE
)
```

The PDF appears at
`Results/nat_spatial_comparison_zero/patchFPCA_Nat_comparison_zero.pdf`.
Rerun with `run_residuals = TRUE` for the grouped Moran diagnostics; fit
checkpoints are reused. Compare the original figures with this unbuffered run
only after checking that Nat's older CSVs used the same patch correction and
the same FPCA response construction and row inclusion.

The `patchFPCA` package already bundles the sdmTMB SPDE report and its public
`render_spatial_report()` wrapper. The new preparation script isolates the
expensive input step so the 0 m Nat comparison can use the saved table without
rendering the older report or its knitr lazy-load cache.

## Run from the project root

Use the updated files together in `spatial-report/`. Do not source the older
helper copy inside `recovered_10m_e0fc649d1f33/` for this report.

```r
source("spatial-report/run_nat_comparison.R")

render_nat_comparison(
  project_root = getwd(),
  prepared_data = "Results/spatial_autocorrelation_10m/spatial_model_data.rds",
  previous_results_dir = "spatial-report/recovered_10m_e0fc649d1f33/results"
)
```

Run this in the existing analysis R installation. In addition to the original
spatial-analysis packages, `digest`, `rmarkdown`, `bookdown`, Pandoc and a LaTeX
installation are required. The runner checks R packages before doing analysis.
It only loads the saved table and never reads, joins, or dissolves polygons.
Calling `source()` alone does not start any work.

The PDF is written to
`Results/nat_spatial_comparison_10m/patchFPCA_Nat_comparison_10m.pdf`.
This directory also contains `progress.log`, CSVs and `checkpoints/`.
Use `output_dir` to choose another location. Keep checkpoints with their original
directory: the fit-summary checkpoint contains absolute paths to fitted models.
The source table and earlier results are left intact.

`previous_results_dir` can be omitted if exactly one prior model suite can be
found. An explicitly wrong directory is an error; the runner will not silently
substitute new fits. Use `previous_results_dir = ""` for an intentional fresh
fit. For an already prepared zero-metre analysis, supply its RDS and its matching
previous-fit directory; the correction label and settings are read from that
RDS and determine a separate default output directory.

## What changes

The same observations, FPCA1 response and factor levels are used throughout.

| Analysis | Comparisons |
| --- | --- |
| Variance partitioning | Two area transformations × coordinate trend/dbMEM × point on surface/centroid: eight partitions |
| Mixed models | Each area transformation: baseline, coordinate trend, point SPDE at 10/20/40 km cutoffs, and centroid SPDE at the primary 20 km cutoff |
| Residual checks | Baseline and primary point SPDE for each area transformation, at the saved residual grouping scales |

The actual mesh settings are taken from the saved RDS. The table gives the
settings used in the current 10 m analysis. Centroid SPDE is optional according
to the saved `run_centroid_sensitivity` setting; both supports are used for RDA.

Area is either standardized `log(area_sq_m)` (equivalent to standardized
`log(area_ha)`) or standardized `log1p(area_sq_m / 10000)`, matching Nat's
`log(Area_ha + 1)` expression. Coordinates use `x + y + x:y`; longitude and
latitude are reconstructed from the saved representative locations and
centered/scaled. MEM and SPDE still use projected kilometres. MEM selection is
repeated for each area transformation and support.

This is a controlled comparison of Nat-style specifications on the current
data, not an exact historical reproduction. The construction of Nat's earlier
`mean_FPCA1`, patch correction, included rows and original coordinates still
need reconciliation. Historical manually entered plotting fractions are not
treated as newly fitted results. Species have random intercepts in the mixed
models, with common slopes and a common spatial field.

With three point mesh resolutions and centroid sensitivity, there are twelve
distinct mixed models. Five original log-area fits can be reused if they match;
**seven fits are new**. Imported fits must match formula, version, response,
predictors, patch keys, row order, and spatial support. A mismatch stops with a
message. Use the original sdmTMB version for its saved models, or deliberately
start a fresh fit. This is not a cheap rerender: the genuinely new fits and
residual simulations may still take substantial time on 3.3 million rows.

## Resume after a failure

Run the **same command** again. Completed stages are loaded from checked RDS
files keyed to inputs, parameters, package versions and relevant function code.
Each fitted model is saved before coefficient extraction and diagnostics.
Grouped DHARMa simulations are saved before Moran testing; the original
patch-level simulation matrices are removed from grouped objects before saving.
Changing the Moran extraction helper reruns tests, not completed fits or
unchanged grouped simulations. Progress is recorded immediately in the log.

The new report uses **`cache = FALSE`**. The old report's knitr lazy-load cache
caused the long-vector error and cannot recover previously uncached work.
Use this runner for the new analysis, rather than rendering the historical
`04_spatial_autocorrelation.Rmd` or calling the package's old render wrapper.

The DHARMa fix reads `test$statistic[c("observed", "expected")]` and
`test$p.value`; DHARMa does not store those Moran values in `test$estimate`.
If the failed earlier run did not save simulations, those simulations must be
calculated again once. Existing model fits can still be reused.

To obtain the comparison PDF before the expensive diagnostic stage:

```r
render_nat_comparison(
  project_root = getwd(),
  previous_results_dir = "spatial-report/recovered_10m_e0fc649d1f33/results",
  run_residuals = FALSE
)
```

The PDF explicitly marks residual diagnostics as pending. Rerun with
`run_residuals = TRUE` to complete them using the same model checkpoints.
Raw simulation matrices are still generated in memory: grouping reduces
checkpoint size, not the peak memory required for simulation.

## Validation

From the repository root:

```r
source("spatial-report/tests/test_nat_comparison.R")
```

The tests cover area units, input preservation and validation, checkpoint
resumption/failure, saved-fit checks, and Moran extraction. When the relevant
packages are installed, they also compare variance partitioning with direct
`vegan::varpart()` and compact grouped residuals with DHARMa's original output.
The base-R checks can run without fitting spatial models. They do not validate
convergence or numerical results of the full user-data analysis.
