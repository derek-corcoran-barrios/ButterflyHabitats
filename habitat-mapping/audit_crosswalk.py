"""Audit the tabular links among survey habitats, class rules, and expert scores.

This reads the original Excel files without changing them or generating maps.
The six label pairings below are for auditing only. README2.Rmd does not use
them when it looks up habitat rasters.
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from pathlib import Path

from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parent.parent
PAIRED_LABELS = {
    "Dyrkede marker (I omdrift)": "Dyrkede marker (i omdrift)",
    "Højmose, nedbrudt højmose og hængesæk": "Højmose, Nedbrudt højmose og Hængesæk",
    "Ikke dyrkede, ikke bebyggede åbne områder, inklusive ruderater":
        "Ikke dyrkede, ikke bebyggede åbne områder inklusive ruderater.",
    "Mark kanter og markskel": "Mark-kanter og markskel",
    "Skovbevokset tørvmose": "Skovbevokset tørvemose",
    "Skovmose/Sumpskov": "Sumpskov/skovmose",
}


def rows(path: Path, header: tuple[str, ...]) -> list[tuple]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing {path}; supply it with the corresponding option")
    workbook = load_workbook(path, read_only=True, data_only=True)
    try:
        if len(workbook.worksheets) != 1:
            raise ValueError(f"{path}: expected one worksheet")
        values = list(workbook.active.values)
    finally:
        workbook.close()
    if not values or tuple(values[0]) != header:
        raise ValueError(f"{path}: unexpected header {values[0] if values else None}")
    return values[1:]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classes", type=Path, default=ROOT / "Classes_Butterfiles_.xlsx")
    parser.add_argument("--experts", type=Path, default=ROOT / "Majority_Expert_Opinions.xlsx")
    parser.add_argument(
        "--descriptions", type=Path, default=Path(__file__).with_name("habitat_description.csv")
    )
    args = parser.parse_args()

    classes = rows(args.classes, (
        "habitat", "Narrow", "Broad ", "Additional layers",
        "extracted_text_05", "extracted_text_09", "extracted_text_12"
    ))
    experts = rows(args.experts, ("art", "Habitat", "Majority", "proportion"))
    with args.descriptions.open(encoding="utf-8-sig", newline="") as handle:
        descriptions = list(csv.DictReader(handle))

    names = [row[0] for row in classes]
    if len(classes) != 34 or len(set(names)) != 34:
        raise ValueError("Expected 34 distinct class-table habitats")
    if any(not row[1] for row in classes):
        raise ValueError("Every class-table habitat needs a Narrow rule")
    if [row["Habitat"] for row in descriptions] != names:
        raise ValueError("Class-table and description names/order do not agree")

    by_species = defaultdict(list)
    nonzero_by_habitat = Counter()
    for species, raw_habitat, score, _ in experts:
        label = re.sub(r"\s*\(0-3\)$", "", raw_habitat).strip()
        canonical = PAIRED_LABELS.get(label, label)
        if canonical not in names:
            raise ValueError(f"Unpaired expert habitat: {label!r}")
        if str(score) not in {"0", "1", "2", "3"}:
            raise ValueError(f"Invalid majority score: {species!r}, {label!r}, {score!r}")
        by_species[species].append(canonical)
        if str(score) != "0":
            nonzero_by_habitat[label] += 1

    if len(by_species) != 7 or len(experts) != 7 * 34:
        raise ValueError("Expected seven species and 238 expert-score rows")
    for species, labels in by_species.items():
        if len(labels) != 34 or set(labels) != set(names):
            raise ValueError(f"Missing or duplicated habitat for {species!r}")

    n_broad_fallback = sum(
        row[2] is None or "as narrow" in str(row[2]).lower() for row in classes
    )
    n_notes = sum(bool(row[3]) for row in classes)
    print("Class/descriptions: 34 habitats in matching order.")
    print(f"Class rules: {n_broad_fallback} Broad fallbacks; {n_notes} Additional layers notes.")
    print("Expert scores: seven species × 34 habitats; 238 valid majority scores.")
    print("Six expert labels differ exactly from their class-table label:")
    for source, target in PAIRED_LABELS.items():
        if source not in [re.sub(r"\s*\(0-3\)$", "", row[1]).strip() for row in experts]:
            raise ValueError(f"Documented expert alias missing: {source!r}")
        print(f"  {source} -> {target} ({nonzero_by_habitat[source]} nonzero scores)")
    print("Audit only: these pairings are not applied by README2.Rmd.")
    print("Check generated habitat rasters and all non-executable workbook notes separately.")


if __name__ == "__main__":
    main()
