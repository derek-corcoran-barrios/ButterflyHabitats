
<!-- README.md is generated from README.Rmd. Please edit that file -->

## Overview

This repository aims to transform expert opinion data into species
distribution maps by linking habitat classifications from expert
assessments to existing spatial basemaps.

## Loading Necessary Packages

We begin by loading the required R packages:

``` r
library(readxl)
library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
library(terra)
#> terra 1.8.29
library(foreign)
library(stringdist)
#> 
#> Attaching package: 'stringdist'
#> The following object is masked from 'package:terra':
#> 
#>     extract
```

## Reading the Expert Opinion Table

We load the expert opinion data from an Excel file:

``` r
Experts <- readxl::read_xlsx("Majority_Expert_Opinions.xlsx")
```

## Extracting and Cleaning Unique Habitat Names

The first step is to extract all unique habitat names from the expert
table and clean them by removing specific formatting artifacts (e.g.,
numerical indicators like `(0-3)`).

``` r
UniqueHabs <- unique(Experts$Habitat)
UniqueHabs_clean <- trimws(gsub("\\s*\\(0-3\\)$", "", UniqueHabs))
```

This process results in 34 distinct habitat categories that need to be
matched with habitat classifications from the spatial basemap.

## Loading Basemap Habitat Classifications

To perform the matching, we extract unique habitat classifications from
the attribute table (`.dbf` file) of the basemap.

``` r
lu_00 <- foreign::read.dbf("Basemap/lu_00_2021.tif.vat.dbf")

C_05 <- unique(as.character(lu_00$C_05))
C_09 <- unique(as.character(lu_00$C_09))
C_12 <- unique(as.character(lu_00$C_12))

# Clean C_12 by removing numbers and trimming whitespace
C_12 <- trimws(gsub("[0-9]", "", C_12))
```

## Creating a Dataframe for Habitat Matching

We construct a dataframe to store the original and cleaned habitat names
along with their corresponding matches in the basemap data.

``` r
DF <- data.frame(
  unique_habs = UniqueHabs,
  clean_unique_habs = UniqueHabs_clean,
  c_05 = NA,
  c_09 = NA,
  c_12 = NA
)
```

## Defining a String Matching Function

To find the best match for each habitat name, we use the Levenshtein
distance, which measures the similarity between two strings. The
function returns the closest matching habitat name from the provided
list of candidates.

``` r
find_closest <- function(target, candidates) {
  # Compute Levenshtein distances between the target and candidate habitat names
  distances <- stringdist(target, candidates, method = "lv")
  # Return the most similar match
  candidates[which.min(distances)]
}
```

## Performing Habitat Matching

We apply the string matching function to find the closest corresponding
habitat name in the basemap classifications for each expert-identified
habitat.

``` r
DF$c_05 <- sapply(DF$clean_unique_habs, find_closest, candidates = C_05)
DF$c_09 <- sapply(DF$clean_unique_habs, find_closest, candidates = C_09)
DF$c_12 <- sapply(DF$clean_unique_habs, find_closest, candidates = C_12)
```

## Reviewing and Exporting the Results

We display the final table for review:

| unique_habs                                                          | clean_unique_habs                                              | c_05                               | c_09                               | c_12                                       |
|:---------------------------------------------------------------------|:---------------------------------------------------------------|:-----------------------------------|:-----------------------------------|:-------------------------------------------|
| Avneknippemose (0-3)                                                 | Avneknippemose                                                 | Avneknippemose                     | Avneknippemose                     | Jernbane                                   |
| Dyrkede marker (I omdrift) (0-3)                                     | Dyrkede marker (I omdrift)                                     | Frit areal (overdrev)              | Frit areal (overdrev)              | Ikke kortlagt                              |
| Forstæder og villakvarterer (0-3)                                    | Forstæder og villakvarterer                                    | Frit areal (overdrev)              | Frit areal (overdrev)              | Andet bebyggelse                           |
| Grøftekanter (0-3)                                                   | Grøftekanter                                                   | Golfbane                           | Golfbane                           | Natur, tør                                 |
| Højmose, nedbrudt højmose og hængesæk (0-3)                          | Højmose, nedbrudt højmose og hængesæk                          | Nedbrudt højmose                   | Nedbrudt højmose                   | Høj bebyggelse                             |
| Ikke dyrkede, ikke bebyggede åbne områder, inklusive ruderater (0-3) | Ikke dyrkede, ikke bebyggede åbne områder, inklusive ruderater | Strandvold med flerårig vegetation | Strandvold med flerårig vegetation | Landbrug, intensivt, midlertidige afgrøder |
| Kildevæld (0-3)                                                      | Kildevæld                                                      | Kildevæld                          | Kildevæld                          | Skov                                       |
| Klitlavninger (0-3)                                                  | Klitlavninger                                                  | Klitlavning                        | Klitlavning                        | Bygning                                    |
| Klitter (0-3)                                                        | Klitter                                                        | Klit                               | Klit                               | Erhverv                                    |
| Krat (0-3)                                                           | Krat                                                           | Krat                               | Krat                               | Hav                                        |
| Kyst-skrænter (0-3)                                                  | Kyst-skrænter                                                  | Skrænt                             | Skrænt                             | Natur, tør                                 |
| Landbrugsbebyggelse, nedlagte landbrug mm (0-3)                      | Landbrugsbebyggelse, nedlagte landbrug mm                      | Lav bebyggelse                     | Lav bebyggelse                     | Landbrug, intensivt, permanente afgrøder   |
| Landsbyer (0-3)                                                      | Landsbyer                                                      | Land                               | Land                               | Vandløb                                    |
| Levende hegn (0-3)                                                   | Levende hegn                                                   | Strandeng                          | Strandeng                          | Jernbane                                   |
| Lysåben skov (0-3)                                                   | Lysåben skov                                                   | Ege-blandskov                      | Ege-blandskov                      | Skov                                       |
| Mark kanter og markskel (0-3)                                        | Mark kanter og markskel                                        | Ukultiveret areal                  | Ukultiveret areal                  | Lav bebyggelse                             |
| Midtby (centrum af større byer) (0-3)                                | Midtby (centrum af større byer)                                | Skovbevoksede tørvemoser           | Skovbevoksede tørvemoser           | Andet bebyggelse                           |
| Næringsfattig skov (0-3)                                             | Næringsfattig skov                                             | Vinteregeskov                      | Vinteregeskov                      | Natur, tør                                 |
| Næringsfattig våd eng (0-3)                                          | Næringsfattig våd eng                                          | Tidvis våd eng                     | Tidvis våd eng                     | Natur, våd                                 |
| Næringsrig skov (0-3)                                                | Næringsrig skov                                                | Vinteregeskov                      | Vinteregeskov                      | Natur, tør                                 |
| Næringsrig våd eng (0-3)                                             | Næringsrig våd eng                                             | Tidvis våd eng                     | Tidvis våd eng                     | Natur, våd                                 |
| Overdrev (0-3)                                                       | Overdrev                                                       | Overdrev                           | Overdrev                           | Bykerne                                    |
| Rigkær (0-3)                                                         | Rigkær                                                         | Rigkær                             | Rigkær                             | Skov                                       |
| Skovbevokset tørvmose (0-3)                                          | Skovbevokset tørvmose                                          | Skovbevoksede tørvemoser           | Skovbevoksede tørvemoser           | Skov, våd                                  |
| Skovkanter (0-3)                                                     | Skovkanter                                                     | Skovklit                           | Skovklit                           | Skov                                       |
| Skovlysninger (0-3)                                                  | Skovlysninger                                                  | Skovfyr                            | Skovfyr                            | Bygning                                    |
| Skovmose/Sumpskov (0-3)                                              | Skovmose/Sumpskov                                              | Strandsump                         | Strandsump                         | Skov                                       |
| Strandeng (0-3)                                                      | Strandeng                                                      | Strandeng                          | Strandeng                          | Jernbane                                   |
| Strandoverdrev (0-3)                                                 | Strandoverdrev                                                 | Surt overdrev                      | Surt overdrev                      | Erhverv                                    |
| Tæt skov (0-3)                                                       | Tæt skov                                                       | Skov                               | Skov                               | Skov                                       |
| Tør hede (0-3)                                                       | Tør hede                                                       | Tør hede                           | Tør hede                           | Jernbane                                   |
| Vandløbskanter (0-3)                                                 | Vandløbskanter                                                 | Vandloebskant                      | Skydebane                          | Vandløb                                    |
| Vejkanter og vejskråninger (0-3)                                     | Vejkanter og vejskråninger                                     | Vinteregeskov                      | Vinteregeskov                      | Natur, våd                                 |
| Våd hede (0-3)                                                       | Våd hede                                                       | Våd hede                           | Våd hede                           | Jernbane                                   |

Finally, we export the matched data to an Excel file for further
analysis or verification.

``` r
openxlsx::write.xlsx(DF, "Comparison.xlsx")
```
