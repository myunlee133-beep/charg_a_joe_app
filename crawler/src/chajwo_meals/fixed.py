"""Curated, undated fixed-menu reference catalog owned by the Chajwo project.

The catalog is not an assertion that menus are on sale on a particular day.
Review source terms and prices before making it available publicly.
"""
from __future__ import annotations

import csv
import hashlib
from pathlib import Path

FIXED_RESTAURANTS = frozenset({"버거운버거", "공대간이식당"})
CATALOG_COLUMNS = (
    "restaurant", "building_number", "building_name", "floor", "category",
    "menu_name", "price_variant", "price_won", "price_raw", "price_status",
    "source_url", "observed_on", "note",
)
CATALOG_PATH = Path(__file__).resolve().parent / "data" / "fixed_menu_catalog.csv"


def load_fixed_catalog(path: Path | None = None) -> list[dict]:
    """Read project-maintained catalog; reject malformed entries and duplicate options."""
    path = Path(path) if path is not None else CATALOG_PATH
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not set(CATALOG_COLUMNS).issubset(reader.fieldnames or []):
            raise ValueError("fixed catalog: missing required columns")
        rows = list(reader)
    if not rows:
        raise ValueError("fixed catalog: empty")
    seen: set[tuple[str, str, str]] = set()
    for row in rows:
        if row["restaurant"] not in FIXED_RESTAURANTS or not row["menu_name"].strip():
            raise ValueError("fixed catalog: unknown restaurant or blank menu")
        key = (row["restaurant"], row["menu_name"], row["price_variant"])
        if key in seen:
            raise ValueError(f"fixed catalog: duplicate option {key}")
        seen.add(key)
        value = row["price_won"].strip()
        if value:
            if not value.isascii() or not value.isdigit() or int(value) <= 0:
                raise ValueError(f"fixed catalog: invalid price {value}")
            row["price_won"] = int(value)
        else:
            row["price_won"] = None
        if row["price_status"] not in {"published_price", "needs_review", "trailing_zero_corrected"}:
            raise ValueError("fixed catalog: invalid price_status")
        if row["price_won"] is None and row["price_status"] != "needs_review":
            raise ValueError("fixed catalog: missing price must be marked for review")
    return rows


def fixed_item_rows(catalog: list[dict]) -> list[dict]:
    """Return menu_items-compatible rows without pretending a static menu is a dated meal."""
    items = []
    for row in catalog:
        identity = "|".join(("fixed", row["restaurant"], row["menu_name"], row["price_variant"]))
        key = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:20]
        items.append({
            "record_id": key, "source_date": "", "source": "snuco",
            "building_number": row["building_number"], "building_name": row["building_name"],
            "restaurant": row["restaurant"], "meal_type": "FIXED",
            "menu_name": row["menu_name"], "price_won": row["price_won"],
            "no_meat_label": None, "source_url": row["source_url"],
            "price_variant": row["price_variant"], "data_origin": "fixed_catalog",
            "price_status": row["price_status"], "restaurant_unit": row["restaurant"],
            "price_raw": row.get("price_raw", ""),
        })
    return items
