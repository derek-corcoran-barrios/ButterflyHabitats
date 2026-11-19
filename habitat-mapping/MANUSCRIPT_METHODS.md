# Draft manuscript text: habitat construction

This text was prepared from `AIRECOMEND.py`, the two CSV snapshots and the
[raster workflow](../README2.Rmd). **It has not been inserted into the shared
manuscript by this repository change.** The final class workbook and the
record of how model recommendations were reviewed were not available.

Before pasting, the authors should add (a) the source citations marked 1–3
in the descriptions, (b) basemap and EcoDes citations and versions, and (c)
the reviewers and decision criteria that produced the approved narrow/broad
class lists. Do not claim the LLM rated species suitability.

**Where to insert manually:** In the main manuscript, replace the literal
`Text?.` below “Habitat mapping on the landscape of Denmark.” In Supplementary
Methods, add the two detailed subsections below under the existing “Habitat
definitions” heading, before the sentence “FPCA analysis was repeated across
the six habitat definitions combining:”. Keep the existing broad/narrow and
quality-threshold list, adjusting repeated phrasing if necessary.

## Main manuscript: “Habitat mapping on the landscape of Denmark”

The 34 conceptual habitat categories used in the expert survey were linked
to Denmark's land-use basemap in two stages. First, we supplied each habitat
name and ecological description, together with the available C_05, C_09
and C_12 basemap labels, to GPT-4o mini (temperature 0). The model proposed
candidate land-use classes and a rationale for each habitat at each
classification level. These proposals were retained as an intermediate
crosswalk; the final class table specified a narrow and a broad set of
basemap classes for each habitat. Where no broader set was specified, the
broad definition used the narrow set. We matched the selected labels to
the basemap's value attribute table and created binary habitat masks on
its 10 m grid. Where specified for a habitat, EcoDes vegetation-density
and canopy-height layers, forest-edge and forest-gap masks, or distance to
the coast further constrained its extent. For each species, we multiplied
the relevant habitat masks by the majority expert suitability score (0,
0.3, 0.7 or 1) and assigned each pixel the maximum weighted value. The
resulting ordinal suitability maps were thresholded to include high only,
high plus medium, or high plus medium plus low suitability; contiguous
selected cells defined habitat patches.

## Supplementary Methods: LLM-assisted habitat-to-basemap crosswalk

We compiled names and ecological descriptions for the 34 conceptual habitat
categories used in the expert survey (`habitat_description.csv`). To propose
correspondences with the 2021 Danish land-use basemap, a Python script
(`AIRECOMEND.py`) sent each name and description, separately with the
available labels from the basemap's C_05, C_09 and C_12 classification fields,
to GPT-4o mini through LangChain's `ChatOpenAI` interface. The prompt
requested a list of matching basemap classes and a short explanation; the
script set temperature to 0 and top-p to 0.95. It wrote the returned
recommendations for all 34 habitats and three classification fields to
`habitat_layer_mapping_intermediate.csv`. This file contains model-generated
candidate matches and rationales, not final raster rules or species
suitability scores. The final crosswalk (`Classes_Butterfiles_.xlsx`)
specified separate Narrow and Broad class lists for each habitat.

**Author insertion required:** Describe who reviewed the model output and
how the final narrow and broad definitions and additional structural rules
were selected or amended. The current files do not record that step.

## Supplementary Methods: mapping and suitability rasters

The final class labels were matched to the value attribute table of the
national land-use basemap (`lu_00_2021.tif`) at C_05, C_09 or C_12, then
translated to raster value codes. Separate binary masks for each habitat
were produced under Narrow and Broad definitions at 10 × 10 m resolution
in the basemap's projected UTM32 EUREF89 coordinate system. A missing or
“as narrow” Broad entry was assigned the corresponding Narrow definition.
Some habitats also used constraints encoded in the crosswalk's Additional
layers field: EcoDes high or low vegetation density (>90% or <50%), a 200 m
forest-edge band, forest gaps with canopy height <2 m and area >400 m², or
a 200 m coastal band, as relevant to that habitat.

The expert suitability assessment was a separate input. For each of seven
butterfly species, the majority score for each conceptual habitat ranged
from 0 (not habitat) to 3 (high quality). The raster workflow excluded
score-0 combinations and mapped scores 1, 2 and 3 to 0.3, 0.7 and 1.0.
Each species–habitat mask was multiplied by its score, and the pixel-wise
maximum across contributing habitats produced a species-specific ordinal
suitability raster for each mapping definition. These values are suitability
classes, not occurrence probabilities. We formed three nested binary maps:
high quality only; high plus medium; and high plus medium plus low. Contiguous
suitable cells were polygonized as patches. Distances used later for
connectivity were measured between patch boundaries.
