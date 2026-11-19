"""Validate the archived habitat recommendation snapshot without API calls."""

from __future__ import annotations

import csv
from pathlib import Path

HERE = Path(__file__).resolve().parent


def read_csv(name: str, columns: list[str]) -> list[dict[str, str]]:
    with (HERE / name).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != columns:
            raise ValueError(f"{name}: expected columns {columns}, got {reader.fieldnames}")
        rows = list(reader)
    if len(rows) != 34:
        raise ValueError(f"{name}: expected 34 habitats, got {len(rows)}")
    if any(not all(value and value.strip() for value in row.values()) for row in rows):
        raise ValueError(f"{name}: empty required value")
    names = [row["Habitat"] for row in rows]
    if len(set(names)) != len(names):
        raise ValueError(f"{name}: duplicate habitat name")
    return rows


def main() -> None:
    input_rows = read_csv("habitat_description.csv", ["Habitat", "Description"])
    proposal_rows = read_csv(
        "habitat_layer_mapping_intermediate.csv",
        ["Habitat", "C_05 Recommendation", "C_09 Recommendation", "C_12 Recommendation"],
    )
    if [row["Habitat"] for row in input_rows] != [row["Habitat"] for row in proposal_rows]:
        raise ValueError("Input and output habitat names or their order differ")
    print("OK: 34 matching habitats; 102 nonempty candidate recommendations.")
    print("This check does not validate ecological correctness or the final crosswalk.")


if __name__ == "__main__":
    main()
