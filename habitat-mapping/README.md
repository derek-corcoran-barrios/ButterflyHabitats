# From survey habitat descriptions to Danish habitat maps

This directory documents the **candidate class recommendation** stage of the
ButterflyHabitats mapping workflow. The existing [raster workflow](../README2.Rmd)
documents the subsequent conversion of an approved narrow/broad class crosswalk
to habitat masks and species maps. These are separate decisions: the language
model proposed class matches; experts supplied species–habitat suitability
scores in [`Majority_Expert_Opinions.xlsx`](../Majority_Expert_Opinions.xlsx).

## What is here

| File | Role |
| --- | --- |
| `habitat_description.csv` | Names and Danish descriptions of 34 survey habitats. The numeric source markers in descriptions still need bibliographic attribution. |
| `AIRECOMEND.py` | Unmodified historical Python script for generating candidate basemap matches. |
| `habitat_layer_mapping_intermediate.csv` | Saved intermediate output: 34 habitats, each with a C_05, C_09 and C_12 recommendation. The entries are serialized LangChain `AIMessage` representations, **not** an approved class table. |
| `validate_inputs.py` | Checks row correspondence and completeness of this snapshot without making API calls. |
| `MANUSCRIPT_METHODS.md` | Draft text explaining both mapping stages; author checks are listed before the text. |

The original script contains 152 C_05, 198 C_09 and 23 C_12 candidate labels.
For each habitat it supplied the name, description and one of those label lists
in a prompt to `gpt-4o-mini` through `langchain_openai.ChatOpenAI`, with
`temperature=0` and `top_p=0.95`. It requested a list of classes and an
explanation separately at each level: **34 × 3 = 102 calls** for a complete run.
It saved after each habitat. The intermediate CSV has a complete row for each
of the 34 input habitats in the same order.

Check the snapshot without calling the API:

```bash
cd habitat-mapping
python validate_inputs.py
```

The original script can be examined or rerun in a **separate working copy**
with Python packages `pandas`, `python-dotenv` and `langchain-openai`, and an
`OPENAI_API_KEY` environment variable. Running it makes paid API calls and
overwrites `habitat_layer_mapping_intermediate.csv` in the current directory.
The final printed `.xlsx` filename is a typo: the script writes a `.csv`.
Temperature zero does not guarantee an identical output on a later model
version; the saved CSV is the historical snapshot. Do not commit `.env` files
or API credentials.

## How proposals became maps

The downstream workflow expects `Classes_Butterfiles_.xlsx`, with `Narrow`,
`Broad` and `Additional layers` entries for each conceptual habitat. The
available materials do **not** document who reviewed the LLM proposals, which
proposals were accepted or changed, or the rule for selecting narrow versus
broad classes. This workbook is also **not present in this repository**. The
intermediate recommendations cannot be substituted for it.

Given that final workbook, the [raster workflow](../README2.Rmd) matches class
labels to the `lu_00_2021.tif` value attribute table, makes narrow and broad
binary masks at 10 m resolution, and adds specified EcoDes vegetation-density,
canopy-height, forest-edge, forest-gap or coastal constraints. It rescales
the majority expert scores 0–3 to 0, 0.3, 0.7 and 1, excludes zero scores,
weights the applicable habitat masks, and takes the pixel-wise maximum for
each species. High, high-plus-medium, and high-plus-medium-plus-low thresholds
then define the nested suitable areas from which patches are made. These
scores are ordinal suitability weights, not occurrence probabilities.

The basemap, its VAT, EcoDes rasters, the approved class workbook and generated
rasters are not included here. This repository therefore documents the
recommendation snapshot and raster **procedure**, but does not yet reproduce
the final habitat maps from a fresh checkout.

## Before treating this as a complete methods archive

1. Add the final `Classes_Butterfiles_.xlsx` or an openly shareable, versioned
   export of its `Narrow`, `Broad` and `Additional layers` fields.
2. Record who reviewed the recommendations and the ecological criteria and
   edits used to make the final crosswalk.
3. Attribute the numeric sources `1`, `2`, `3` in the habitat descriptions,
   and confirm permission to distribute those descriptions publicly.
4. Cite the basemap and EcoDes data, identify their versions and access routes,
   and document any final deviations from the existing raster workflow.
