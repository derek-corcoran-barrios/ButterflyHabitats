Butterfly habitat layers and species habitat maps
================

- [1 Overview](#1-overview)
- [2 Packages](#2-packages)
- [3 Input data](#3-input-data)
  - [3.1 Majority expert opinions](#31-majority-expert-opinions)
  - [3.2 Classes butterflies](#32-classes-butterflies)
  - [3.3 How the two tables interact](#33-how-the-two-tables-interact)
- [4 Expert opinions and basemap](#4-expert-opinions-and-basemap)
- [5 Map Excel habitat classes to basemap classes (narrow &
  broad)](#5-map-excel-habitat-classes-to-basemap-classes-narrow--broad)
- [6 \# Build habitat masks (COGs) per habitat (narrow &
  broad)](#6--build-habitat-masks-cogs-per-habitat-narrow--broad)
  - [6.0.1 Quick visual check](#601-quick-visual-check)
- [7 EcoDes structural layers: vegetation density and canopy
  height](#7-ecodes-structural-layers-vegetation-density-and-canopy-height)
  - [7.0.1 Quick visual check](#701-quick-visual-check)
- [8 5. Forest edge distance and 200 m forest
  border](#8-5-forest-edge-distance-and-200-m-forest-border)
  - [8.0.1 Quick visual check](#801-quick-visual-check)
- [9 Forest gaps: canopy \< 2 m inside forest holes \> 400
  m²](#9-forest-gaps-canopy--2-m-inside-forest-holes--400-m²)
  - [9.0.1 Quick visual check](#901-quick-visual-check)
- [10 Distance-to-coast masks (200, 400, 800
  m)](#10-distance-to-coast-masks-200-400-800-m)
  - [10.0.1 Quick visual check](#1001-quick-visual-check)
- [11 Species-specific habitat
  rasters](#11-species-specific-habitat-rasters)
  - [11.0.1 Quick visual check for one
    species](#1101-quick-visual-check-for-one-species)
- [12 9. Example: fusing multiple
  rasters](#12-9-example-fusing-multiple-rasters)
- [13 Notes](#13-notes)

# 1 Overview

This repository documents the workflow used to generate spatial layers
for:

- **Project 1 – Contemporary Habitat Configuration and Population
  Genomics**, and
- the habitat-suitability component that will be reused in **Project 2 –
  Historical / Temporal Habitat Configuration and Population
  Museomics**.

The pipeline:

1.  Reads **expert-opinion habitat suitability** for butterfly species.
2.  Reads a **habitat class mapping** linking conceptual habitats to a
    national land-use basemap.
3.  Maps those habitats to land-use classes via the basemap VAT table.
4.  Generates **binary habitat masks per habitat**.
5.  Derives **structural layers** from EcoDes data (vegetation density,
    canopy height).
6.  Builds **forest-edge distance** and **forest-gap** layers.
7.  Builds **distance-to-coast** masks.
8.  Combines habitat masks, structural layers, and expert opinions into
    species-specific habitat rasters, again for both narrow and broad
    definitions.

Most outputs are written as Cloud Optimized GeoTIFFs (COGs) for
efficient sharing and reuse.

# 2 Packages

``` r
library(terra)
library(tidyverse)   # dplyr, tidyr, stringr, etc.
library(foreign)     # read.dbf
library(readxl)
library(janitor)
library(geodata)
library(tidyterra)
library(patchwork)
# Custom / project packages:

library(SpeciesPoolR)
library(BDRUtils)
```

# 3 Input data

This workflow uses two main tabular inputs plus a national land-use
basemap with an associated Value Attribute Table (VAT).

## 3.1 Majority expert opinions

This file (`Majority_Expert_Opinions.xlsx`) stores the expert-opinion
habitat suitability for each species.

Columns:

- `art` Latin species name (e.g. *Aglais urticae*).

- `Habitat` Text label for the habitat category (e.g. “Grøftekanter
  (0–3)”) that matches the `habitat` column in
  `Classes_Butterfiles_.xlsx` once the “(0–3)” suffix is removed.

- `Majority` Integer score in the range 0–3, summarizing the experts’
  majority score for that species–habitat combination.

- `proportion` Proportion of experts who answered (e.g. 0.6, 0.8). *(Not
  used in the current pipeline; we rely on `Majority`)*.

In the code, we:

1.  Convert `Majority` to numeric.
2.  Rescale it to the range 0–1 by dividing by 3 and rounding to 1
    decimal place.
3.  Filter out combinations with `Majority == 0` (no use of that
    habitat).

We then use this rescaled `Majority` as a **weight** when combining
habitat rasters for each species.

## 3.2 Classes butterflies

This file (`Classes_Butterfiles_.xlsx`) links conceptual habitat
categories to one or more land-cover classes in the national land-use
basemap (`lu_00_2021.tif`).

Columns:

- `habitat` Named habitat category (e.g. *Næringsrig skov*, *Tæt skov*,
  *Lysåben skov*, *Skovkanter*).

- `Narrow`:A list of “narrow” land-use classes that appear in the VAT
  columns `C_12`, `C_09`, or `C_05` of `lu_00_2021.tif`. These strings
  often contain multiple classes separated by dashes/commas; they are
  cleaned and split so each individual class (e.g. “Birk”, “Fyr”,
  “Stilkege-krat”) becomes its own row.

- `Broad` (in the Excel the column is named Broad with a trailing space)
  A broader / wider grouping of classes. Some rows contain the text “as
  narrow”, meaning the broad definition is identical to the narrow one.
  If Broad is missing or “as narrow”, we default to using Narrow here.

- `Additional layers` Optional notes about extra spatial constraints,
  often referring to ECODES layers, e.g.:

  - `ECODES density > 90 %`: use **high-density forest** mask
  - `ECODES density < 50 %`: use **low-density forest** mask
  - `% meters of all forest edges` /
    `Only include edges e.g. 2 metres on both sides ...`: use
    **forest-edge band**
  - `ECODES; areas with hight < 2 metres in forest, and > 20x20 m wihtin forests`:
    use **canopy gaps \< 2 m, \> 400 square meters**
  - `OBS - distance to coast 200 m`: use **coast 200 m mask**

  These are used to **automatically attach ECODES structural masks** to
  those habitats (and thus to the species that use them).

- `extracted_text_05`, `extracted_text_09`, `extracted_text_12`
  Extracted label text corresponding to different VAT columns.

Conceptually:

- `Classes_Butterfiles_.xlsx` says *for habitat H, include these
  land-use classes (narrow vs broad), and optionally combine with these
  ECODES structural layers*.
- The VAT table for `lu_00_2021.tif` tells us *“which numeric codes
  correspond to those class labels”*.
- We then build **binary habitat rasters**, for both a narrow and broad
  definition, and later combine them with species-level expert weights.

## 3.3 How the two tables interact

1.  `Classes_Butterfiles_.xlsx` defines how conceptual habitats map to
    the basemap (`habitat`(`Narrow` / `Broad`): `VALUE` via the VAT),
    and which habitats should be further constrained by ECODES
    structural layers.

2.  `Majority_Expert_Opinions.xlsx` defines, for each species `art`,
    which conceptual habitats it uses and with what weight (`Majority`).

3.  The **species habitat rasters** in `SpeciesHabs/` are built by:

    - starting from the relevant habitat masks in `Habitats/` (narrow
      and/or broad),
    - for some habitats, chaining in extra ECODES structural layers (low
      density, high density, forest edges, canopy gaps, coast 200 m),
    - multiplying each masked habitat by the expert weight `Majority`
      for that species, and
    - taking the pixel-wise maximum across all contributing habitats for
      that species.

So species that depend on **low-density forest**, **forest edges**, or
**coastal areas** automatically get those structural constraints
applied, but only for the relevant habitats.

# 4 Expert opinions and basemap

``` r
# Expert opinions (0–3) scaled to 0–1 and filtered
Expert_opinion <- read_excel("Majority_Expert_Opinions.xlsx") |>
  dplyr::mutate(Majority = round(as.numeric(Majority) / 3, 1)) |>
  dplyr::filter(Majority > 0)

# Basemap raster (land-use)
raster_file <- "Basemap/lu_00_2021.tif"
r <- rast(raster_file)

DK <- geodata::gadm("Denmark", level = 0, path = getwd()) |>
  terra::project(terra::crs(r))

# Value Attribute Table (VAT) for the basemap
dbf_data <- read.dbf("Basemap/lu_00_2021.tif.vat.dbf")

# Clean up the C_12 labels: drop digits, trim whitespace
dbf_data$C_12 <- trimws(gsub("[0-9]", "", dbf_data$C_12))
```

# 5 Map Excel habitat classes to basemap classes (narrow & broad)

We build two long tables:

- `Long_narrow`: mapping `habitat` to VAT `VALUE` codes using the
  **Narrow** column,
- `Long_broad`: mapping `habitat` to VAT `VALUE` codes using the
  **Broad** column.

``` r

class_map_raw <- readxl::read_excel("Classes_Butterfiles_.xlsx")

# Handle possible trailing space in the column name ("Broad " vs "Broad")
if ("Broad " %in% names(class_map_raw) && !"Broad" %in% names(class_map_raw)) {
  class_map_raw <- dplyr::rename(class_map_raw, Broad = `Broad `)
}

class_map <- class_map_raw |>
  dplyr::mutate(
    # Interpret "as narrow" (case-insensitive) in Broad as "use Narrow"
    Broad = ifelse(
      stringr::str_detect(Broad, regex("as narrow", ignore_case = TRUE)),
      Narrow, Broad
    ),
    # If Broad is NA or empty, also fall back to Narrow
    Broad = ifelse(is.na(Broad) | trimws(Broad) == "", Narrow, Broad)
  )

fyr_types <- c(
  "Bjergfyr", "Frans bjergfyr", "Østrigsk fyr", "Skovfyr",
  "Fransk bjergfyr", "Weymouthsfyr", "Østrigsk fyr", "Skovfyr"
)


# Helper to clean and split a given habitat column ("Narrow" or "Broad")
clean_habitat_column <- function(df, col_name) {

  # 1) Do all the string cleaning and splitting
  df_long <- df |>
    dplyr::select(habitat, Narrow = dplyr::all_of(col_name)) |>
    dplyr::mutate(
      # Fix various naming issues
      Narrow = stringr::str_replace_all(Narrow, "Stilkege-krat", "Stilkege krat"),
      Narrow = stringr::str_replace_all(
        Narrow,
        "Elle- og askeskov ved vandløb, søer og væld",
        "Elle og askeskov ved vandløb, søer og væld"
      ),
      Narrow = stringr::str_replace_all(Narrow, "Ege-blandskov", "Ege blandskov"),
      Narrow = stringr::str_replace_all(
        Narrow,
        stringr::fixed("Lav bebyggelse (Low buildings), Have"),
        "Lav bebyggelse"
      ),
      Narrow = stringr::str_replace_all(
        Narrow,
        stringr::fixed("Overdrev (Slette)"),
        "Slette, Overdrev (Slette)"
      ),
      Narrow = stringr::str_replace_all(
        Narrow,
        stringr::fixed("Overdrev (overdrev)"),
        "Slette, Overdrev (overdrev)"
      ),
      Narrow = stringr::str_replace_all(
        Narrow,
        stringr::fixed("Overdrev (græsset)"),
        "Slette, Overdrev (græsset)"
      ),
      Narrow = stringr::str_replace_all(Narrow, stringr::fixed("Kilder"), "Kildevæld"),
      Narrow = stringr::str_replace_all(Narrow, stringr::fixed("Ruin"), "Ruin, gravhøj"),
      Narrow = stringr::str_replace_all(Narrow, stringr::fixed("Vandløbskant"), "Vandloebskant")
    ) |>
    dplyr::mutate(Narrow = stringr::str_split(Narrow, "-")) |>
    tidyr::unnest(Narrow) |>
    dplyr::mutate(
      Narrow = stringr::str_trim(Narrow),
      Narrow = stringr::str_remove_all(Narrow, "^,|,$")
    ) |>
    dplyr::filter(
      Narrow != "",
      !is.na(Narrow),
      Narrow != ",",
      Narrow != "NA"
    ) |>
    dplyr::mutate(
      Narrow = stringr::str_replace_all(
        Narrow,
        "Elle og askeskov ved vandløb, søer og væld",
        "Elle- og askeskov ved vandløb, søer og væld"
      ),
      Narrow = stringr::str_replace_all(Narrow, "Stilkege krat", "Stilkege-krat"),
      Narrow = stringr::str_replace_all(Narrow, "Ege blandskov", "Ege-blandskov")
    )

  # 2) Expand generic "Fyr" to all specific Fyr types
  Fyr_expanded <- df_long |>
    dplyr::filter(Narrow == "Fyr") |>
    dplyr::select(habitat) |>
    tidyr::uncount(length(fyr_types)) %>%
    dplyr::mutate(
      Narrow = rep(fyr_types, times = nrow(.) / length(fyr_types))
    )

  # 3) Replace generic "Fyr" rows with the expanded ones
  df_long <- df_long |>
    dplyr::filter(Narrow != "Fyr") |>
    dplyr::bind_rows(Fyr_expanded)

  df_long
}


Long_narrow <- clean_habitat_column(class_map, "Narrow")
Long_broad  <- clean_habitat_column(class_map, "Broad")
```

Now we identify which VAT column (`C_12`, `C_09`, `C_05`) each class
belongs to and assign the corresponding `VALUE` code, separately for
narrow and broad.

``` r
add_vat_values <- function(Long, dbf) {
  Long$layer <- NA_character_
  Long$value <- NA_integer_

  Long$layer[Long$Narrow %in% dbf$C_12] <- "C_12"
  Long$layer[Long$Narrow %in% dbf$C_09] <- "C_09"
  Long$layer[Long$Narrow %in% dbf$C_05] <- "C_05"

  NotHereYet <- Long |>
    dplyr::filter(is.na(layer)) |>
    dplyr::pull(Narrow) |>
    unique()

  if (length(NotHereYet) > 0) {
    message("Classes not found in VAT: ",
            paste(NotHereYet, collapse = ", "))
  }

  Long <- Long |>
    dplyr::filter(!is.na(layer))

  for (i in seq_len(nrow(Long))) {
    col_i <- Long$layer[i]
    val_i <- Long$Narrow[i]
    Long$value[i] <- dbf$VALUE[dbf[[col_i]] == val_i]
  }

  Long
}

Long_narrow <- add_vat_values(Long_narrow, dbf_data)
Long_broad  <- add_vat_values(Long_broad,  dbf_data)

HABS <- sort(unique(class_map$habitat))
dir.create("Habitats", showWarnings = FALSE)
```

# 6 \# Build habitat masks (COGs) per habitat (narrow & broad)

For each habitat, we build two binary rasters:

- `*_narrow.tif` → based on the **Narrow** definition.
- `*_broad.tif` → based on the **Broad** (“wide”) definition.

``` r
for (hab_i in HABS) {

  # NARROW definition
  Temp_narrow <- Long_narrow |>
    dplyr::filter(habitat == hab_i) |>
    dplyr::pull(value)

  if (length(Temp_narrow) > 0) {
    NewRast_narrow <- terra::ifel(as.numeric(r) %in% Temp_narrow, 1, 0)

    out_narrow <- paste0(
      "Habitats/",
      janitor::make_clean_names(hab_i),
      "_narrow.tif"
    )

    SpeciesPoolR::write_cog(NewRast_narrow, out_narrow)
  }

  # BROAD (wide) definition
  Temp_broad <- Long_broad |>
    dplyr::filter(habitat == hab_i) |>
    dplyr::pull(value)

  if (length(Temp_broad) > 0) {
    NewRast_broad <- terra::ifel(as.numeric(r) %in% Temp_broad, 1, 0)

    out_broad <- paste0(
      "Habitats/",
      janitor::make_clean_names(hab_i),
      "_broad.tif"
    )

    SpeciesPoolR::write_cog(NewRast_broad, out_broad)
  }
}
```

### 6.0.1 Quick visual check

<img src="man/figures/README-plot-habitat-example-1.png" width="100%" />

# 7 EcoDes structural layers: vegetation density and canopy height

We derive:

- a high-density and low-density forest mask from EcoDes vegetation
  density, and
- a canopy \< 2 m mask from EcoDes canopy height.

``` r
terraOptions(memfrac = 0.8, tempdir = "D:/WD_R/temp")
Sys.setenv(GDAL_NUM_THREADS = 10)
```

``` r
Density <- rast(
  "o:/Nat_Ecoinformatics/B_Read/Denmark/DK_EcoDes/EcoDes-DK15_v1.1.0/vegetation_density/vegetation_density.vrt"
)

thr <- app(
  Density,
  fun = function(x) cbind(as.integer(x > 9000L), as.integer(x < 5000L)),
  filename = "density_thresholds.tif",
  overwrite = TRUE,
  cores = max(1, parallel::detectCores() / 2),
  wopt = list(
    names    = c("HighDensity", "LowDensity"),
    datatype = "INT1U",
    gdal     = c(
      "COMPRESS=ZSTD", "TILED=YES",
      "BLOCKXSIZE=512", "BLOCKYSIZE=512",
      "NUM_THREADS=ALL_CPUS", "BIGTIFF=IF_SAFER"
    )
  )
)

BDRUtils::write_cog(thr[[1]], "HighDensity.tif")
BDRUtils::write_cog(thr[[2]], "LowDensity.tif")
```

``` r
canopy_height <- rast(
  "o:/Nat_Ecoinformatics/B_Read/Denmark/DK_EcoDes/EcoDes-DK15_v1.1.0/canopy_height/canopy_height.vrt"
)

thr_canopy <- app(
  canopy_height,
  fun = function(x) cbind(as.integer(x < 200L)),
  filename = "canopy_height_bellow_2m.tif",  # note: filename kept as in original code
  overwrite = TRUE,
  cores = max(1, parallel::detectCores() / 2),
  wopt = list(
    names    = c("canopy_height_bellow_2m"),
    datatype = "INT1U",
    gdal     = c(
      "COMPRESS=ZSTD", "TILED=YES",
      "BLOCKXSIZE=512", "BLOCKYSIZE=512",
      "NUM_THREADS=ALL_CPUS", "BIGTIFF=IF_SAFER"
    )
  )
)
```

### 7.0.1 Quick visual check

<img src="man/figures/README-plot-density-canopy-1.png" width="100%" />

# 8 5. Forest edge distance and 200 m forest border

We use a forest mask (`Habitats/skovkanter_narrow.tif`) to compute:

- distance to the nearest forest edge for every pixel, and
- a 200 m band on both sides of the forest edge.

``` r
# Forest edge / forest mask
skovkanterv_narrow <- rast("Habitats/skovkanter_narrow.tif")

x <- skovkanterv_narrow

# Sources for distance: opposite classes
src_nonforest <- ifel(x == 0, 1, NA)  # distance FROM forest cells TO nearest non-forest
src_forest    <- ifel(x == 1, 1, NA)  # distance FROM non-forest cells TO nearest forest

d_to_nonforest <- distance(
  src_nonforest,
  filename = "d_to_nonforest.tif", overwrite = TRUE,
  wopt = list(gdal = c("COMPRESS=LZW", "TILED=YES", "BIGTIFF=YES"))
)

d_to_forest <- distance(
  src_forest,
  filename = "d_to_forest.tif", overwrite = TRUE,
  wopt = list(gdal = c("COMPRESS=LZW", "TILED=YES", "BIGTIFF=YES"))
)

# Distance to the edge = distance to the opposite class
dist_edge <- ifel(x == 1, d_to_nonforest, d_to_forest)
writeRaster(
  dist_edge,
  "dist_to_edge.tif",
  overwrite = TRUE,
  wopt = list(gdal = c("COMPRESS=LZW", "TILED=YES", "BIGTIFF=YES"))
)

# 200 m band on both sides of the edge
edge200 <- dist_edge <= 200
writeRaster(
  edge200,
  "forest_border_200m.tif",
  overwrite = TRUE,
  wopt = list(
    datatype = "INT1U",
    gdal      = c("COMPRESS=LZW", "TILED=YES")
  )
)
```

### 8.0.1 Quick visual check

<img src="man/figures/README-plot-edge-1.png" width="100%" />

# 9 Forest gaps: canopy \< 2 m inside forest holes \> 400 m²

We identify low-canopy patches inside “holes” in forest (clearings)
larger than 400 m², then rasterize them.

``` r
# Canopy < 2 m (1/NA)
canopy_bellow_2 <- rast("canopy_height_bellow_2m.tif")

# Forest raster (assumed 1 = forest, NA or 0 = non-forest)
forestEdge <- rast("Habitats/skovkanter_narrow.tif")

# Forest polygons, split into individual parts
forestEdgePoly <- terra::as.polygons(forestEdge) |>
  terra::disagg()

# Holes inside forest polygons
ForestHoles <- terra::fillHoles(forestEdgePoly, inverse = TRUE)

# Keep holes > 400 m² (~20 x 20 m)
ForestHolesOver400sqmt <- ForestHoles[terra::expanse(ForestHoles) > 400, ]

# Rasterize holes onto canopy grid
ForestHolesOver400sqmtRast <- terra::rasterize(
  ForestHolesOver400sqmt,
  canopy_bellow_2,
  field = 1
)

# Combine low canopy and holes
HolesWithLowCanopy <- canopy_bellow_2 + ForestHolesOver400sqmtRast

# Keep only pixels where both are 1 (sum == 2)
HolesWithLowCanopy <- terra::ifel(HolesWithLowCanopy == 2, 1, NA)

# Convert to polygons and filter by size again
HolesWithLowCanopy <- terra::as.polygons(HolesWithLowCanopy) |>
  terra::disagg()
HolesWithLowCanopy <- HolesWithLowCanopy[terra::expanse(HolesWithLowCanopy) > 400, ]

forest_gaps_canopy_lt2m_400m2 <- terra::rasterize(HolesWithLowCanopy, forestEdge)
BDRUtils::write_cog(forest_gaps_canopy_lt2m_400m2, "forest_gaps_canopy_lt2m_400m2.tif")
```

### 9.0.1 Quick visual check

<img src="man/figures/README-plot-gaps-1.png" width="100%" />

# 10 Distance-to-coast masks (200, 400, 800 m)

We create distance-to-coast rasters and then binary masks within 200,
400, and 800 m of the coast.

``` r
# Denmark boundary in same CRS as basemap r
DK <- geodata::gadm("Denmark", level = 0, path = getwd()) |>
  terra::project(terra::crs(r))

DK_Coast <- terra::rasterize(DK, r, field = NA, background = 1)
DK_Coast_m <- terra::distance(DK_Coast)
DK_Coast_m <- terra::mask(DK_Coast_m, DK)

DK_Coast_200m <- terra::ifel(DK_Coast_m <= 200, 1, 0)
BDRUtils::write_cog(DK_Coast_200m, "DK_Coast_200m.tif")

DK_Coast_400m <- terra::ifel(DK_Coast_m <= 400, 1, 0)
BDRUtils::write_cog(DK_Coast_400m, "DK_Coast_400m.tif")

DK_Coast_800m <- terra::ifel(DK_Coast_m <= 800, 1, 0)
BDRUtils::write_cog(DK_Coast_800m, "DK_Coast_800m.tif")
```

### 10.0.1 Quick visual check

<img src="man/figures/README-plot-coast-1.png" width="100%" />

# 11 Species-specific habitat rasters

We combine the habitat masks and expert opinions to build a final
weighted habitat raster per species (maximum overlap across habitats).

``` r
dir.create("SpeciesHabs", showWarnings = FALSE)

SPP <- unique(Expert_opinion$art)

# Clean up Habitat labels in Expert_opinion
Expert_opinion$Habitat <- trimws(
  gsub("\\s*\\(0-3\\)$", "", Expert_opinion$Habitat)
)

for (i in seq_along(SPP)) {
  spp_name <- SPP[i]
  message("Starting species ", i, ": ", spp_name, " @ ", round(Sys.time()))

  Species <- Expert_opinion |>
    dplyr::filter(art == spp_name)

  Final_rast <- NULL

  for (j in seq_len(nrow(Species))) {
    hab_name <- janitor::make_clean_names(Species$Habitat[j])
    hab_path <- file.path("Habitats", paste0(hab_name, "_narrow.tif"))

    if (file.exists(hab_path)) {
      r_hab <- try(terra::rast(hab_path), silent = TRUE)

      if (inherits(r_hab, "SpatRaster")) {
        r_weighted <- r_hab * Species$Majority[[j]]

        if (is.null(Final_rast)) {
          Final_rast <- r_weighted
        } else {
          # Pixel-wise maximum across habitats
          Final_rast <- max(c(Final_rast, r_weighted))
        }

        message("Habitat ", j, " of ", nrow(Species),
                " ready @ ", round(Sys.time()))
      } else {
        message("Skipping habitat ", j, " (not a valid raster)")
      }
    } else {
      message("Missing file for habitat ", j, " - ", hab_path)
    }
  }

  if (!is.null(Final_rast)) {
    message("Masking species raster @ ", round(Sys.time()))
    Final_rast <- terra::mask(Final_rast, DK)

    out_path <- file.path(
      "SpeciesHabs",
      paste0(janitor::make_clean_names(spp_name), "_narrow_.tif")
    )
    message("Writing COG: ", out_path, " @ ", round(Sys.time()))
    SpeciesPoolR::write_cog(Final_rast, out_path)
  } else {
    message("No valid rasters found for ", spp_name)
  }
}
```

### 11.0.1 Quick visual check for one species

``` r
if (exists("SPP") && length(SPP) > 0) {
  spp_example <- SPP[1]
  spp_file <- file.path(
    "SpeciesHabs",
    paste0(janitor::make_clean_names(spp_example), "_narrow_.tif")
  )

  if (file.exists(spp_file)) {
    spp_rast <- rast(spp_file)
    plot(spp_rast, main = paste("Habitat suitability:", spp_example))
  }
}
```

# 12 9. Example: fusing multiple rasters

As a general pattern, you can fuse a list of rasters by taking the
pixel-wise maximum using `mosaic()`:

``` r
# Example: fuse a list of SpatRasters by pixel-wise maximum
# (replace r1, r2, r3 with real objects)
raster_list  <- list(r1, r2, r3)
fused_raster <- do.call(mosaic, c(raster_list, fun = max))

plot(fused_raster, main = "Fused raster (pixel-wise max)")
```

# 13 Notes

- Many of these steps are computationally heavy. If you just want the
  code in the README without re-running all computations, set
  `eval = FALSE` on the corresponding chunks (already done for most big
  ones).

- Outputs are written as **Cloud Optimized GeoTIFFs** so they can be
  reused in other scripts, GIS software, and shared via the center’s
  data-sharing system for both contemporary and temporal habitat
  analyses.

<!-- -->
