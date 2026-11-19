# From survey habitat descriptions to Danish habitat maps

This directory documents how survey habitat descriptions were linked to Danish
land-cover classes. The [raster workflow](../README2.Rmd) shows the next step,
constructing habitat and species maps. The language model generated **candidate**
class matches. The class workbook supplied for this audit contains the final
Narrow/Broad columns, while the expert-score workbook supplies species-specific
weights. The class workbook is not in the public repository; see the data-use
conditions in `README2.Rmd` before distributing it.

## What is here

| File | Role |
| --- | --- |
| `habitat_description.csv` | Names and Danish descriptions of 34 survey habitats. The numeric source markers in descriptions still need bibliographic attribution. |
| `AIRECOMEND.py` | Unmodified historical Python script for generating candidate basemap matches. |
| `habitat_layer_mapping_intermediate.csv` | Saved intermediate output: 34 habitats, each with a C_05, C_09 and C_12 recommendation. The entries are serialized LangChain `AIMessage` representations, **not** an approved class table. |
| `validate_inputs.py` | Checks row correspondence and completeness of the candidate snapshot without API calls. |
| `audit_crosswalk.py` | Reads the supplied class and expert workbooks, verifies their schemas and 34 × 7 links, and prints exact label differences. Requires Python `openpyxl`. |
| `../Majority_Expert_Opinions.xlsx` | Existing seven-species expert-score table. The supplied copy has the same 238 cell-value rows as the repository copy. |
| `../Classes_Butterfiles_.xlsx` | Final class workbook used by the raster example; reviewed locally for this audit, but not included in the public repository. |
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

The supplied `Classes_Butterfiles_.xlsx` has 34 unique habitats in exactly the
same names and order as `habitat_description.csv`. Its columns are `habitat`,
`Narrow`, `Broad ` (with a trailing space), `Additional layers`, and three
`extracted_text_*` fields. All Narrow fields are populated. Eighteen Broad
fields are blank or say “as narrow”; `README2.Rmd` uses Narrow for those.
Twelve rows have Additional layers notes. The saved intermediate LLM
recommendations are **not** a substitute for these final class rules.
The files do not record who reviewed the recommendations, which suggestions
were accepted or changed, or the ecological criteria behind those decisions.

Given the final class workbook, `README2.Rmd` matches labels to the
`lu_00_2021.tif` value attribute table and constructs narrow and broad
habitat masks on a 10 m grid. Its shown species-raster code recognizes
patterns in the Additional layers text for high or low EcoDes density,
forest-edge bands, forest gaps, and a 200 m coastal band. The other notes
are **not** automatically implemented by those five pattern checks:
the Rigkær / 7230 question, “outside cities” for rural buildings, and
the two notes about treating villages/suburbs together. The road/ditch
notes mention 2 m on either side, while the shown `add_edges200` flag
uses the 200 m forest-border raster. This discrepancy needs checking
against the code and maps actually used in the manuscript.

Expert suitability is a separate input: seven species × 34 habitats =
238 rows in `Majority_Expert_Opinions.xlsx`. The shown raster workflow
maps majority scores 0–3 to 0, 0.3, 0.7 and 1, excludes zero scores,
and takes the maximum weighted mask value at each pixel. High,
high-plus-medium, and high-plus-medium-plus-low thresholds define
nested suitable areas. These ordinal scores are not occurrence probabilities.

### Check the links between the input tables

With the supplied `Classes_Butterfiles_.xlsx` placed at the repository root:

```bash
python -m pip install openpyxl
python habitat-mapping/audit_crosswalk.py
```

The audit checks the class names against descriptions, verifies all seven
species have 34 scores each, and prints the six exact label differences
between the expert table and class workbook. It does **not** edit the
workbooks, apply aliases to the raster code, or validate raster output.
These two differing names cannot be resolved by case or punctuation
cleanup alone:

| Expert-score label | Class-workbook label | Nonzero species scores |
| --- | --- | ---: |
| Skovbevokset tørvmose | Skovbevokset tørvemose | 3 |
| Skovmose/Sumpskov | Sumpskov/skovmose | 5 |

The other four differences involve case or punctuation. `README2.Rmd`
removes only the score suffix, builds raster paths from cleaned expert
labels, and looks up Additional layers using exact label equality.
Check which generated habitat rasters were actually used before
treating the two example scripts as a verified reproduction of the maps.

## To complete the methods archive

1. Confirm that the final class workbook can be shared publicly, then add
   a versioned copy to the repository root (or an accessible, versioned
   export) and record its provenance.
2. Record the expert review and criteria that produced the Narrow/Broad
   rules from the candidate recommendations.
3. Reconcile the six label differences, verify actual habitat and species
   rasters for the eight positive scores associated with the two substantive
   name mismatches, and resolve the Additional layers discrepancies above.
4. Attribute the numeric description sources `1`, `2`, `3` and confirm
   their redistribution rights.
5. Cite/version the basemap and EcoDes inputs and document any deviations
   from the shown raster workflow.
