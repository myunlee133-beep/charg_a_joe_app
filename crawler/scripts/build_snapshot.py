"""Build the app's meal snapshot: the last PAST_DAYS and the next FUTURE_DAYS of dated menus.

Usage: python scripts/build_snapshot.py OUTPUT.json
The school site serves past dates too, so every run rebuilds the whole window from scratch.
Unpublished future days simply come back empty (only fixed food-court menus repeat).
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from chajwo_meals.pipeline import collect, collect_metadata, flatten_entries  # noqa: E402

PAST_DAYS = 30
FUTURE_DAYS = 14


def fold_fixed(menus: list[dict]) -> list[dict]:
    """Menus on the board nearly every day of the window become one date=None row; the rest stay dated."""
    all_days = {m["date"] for m in menus}
    days_per_unit: dict[str, set] = {}
    days_per_menu: dict[tuple, set] = {}
    for m in menus:
        days_per_unit.setdefault(m["unit"], set()).add(m["date"])
        days_per_menu.setdefault((m["unit"], m["meal"], m["name"], m["priceWon"]), set()).add(m["date"])
    fixed: dict[tuple, dict] = {}
    dated = []
    for m in menus:
        key = (m["unit"], m["meal"], m["name"], m["priceWon"])
        unit_days = len(days_per_unit[m["unit"]])
        # Only units that post almost every day qualify, and the menu must be on nearly all of those days.
        if len(all_days) >= 10 and unit_days >= 0.6 * len(all_days) and len(days_per_menu[key]) >= 0.9 * unit_days:
            fixed.setdefault(key, {**m, "date": None})
        else:
            dated.append(m)
    return list(fixed.values()) + dated


def build() -> dict:
    today = datetime.now(ZoneInfo("Asia/Seoul")).date()
    start = today - timedelta(days=PAST_DAYS)
    # collect() caps one call at 31 days, so the window is fetched in two calls.
    rows, errors = collect(start=start, days=PAST_DAYS + 1)
    more, more_errors = collect(start=today + timedelta(days=1), days=FUTURE_DAYS)
    directory, metadata_errors = collect_metadata()
    entries = [e for e in flatten_entries(rows + more) if e["data_origin"] == "observed_page"]
    if not entries:
        raise RuntimeError("No dated meal entries collected")
    # Compact on purpose: the app downloads this whole file. A menu repeated across meal slots is kept once, and a
    # menu that is on the board almost every day (food-court menus) is stored once with date=None meaning "every day".
    seen, menus = set(), []
    for e in entries:
        key = (e["source_date"], e["restaurant_unit"], e["meal_type"], e["menu_name"], e["price_won"])
        if key not in seen:
            seen.add(key)
            menus.append({"date": e["source_date"], "unit": e["restaurant_unit"], "building": e["building_number"],
                          "meal": e["meal_type"], "name": e["menu_name"], "priceWon": e["price_won"]})
    menus = fold_fixed(menus)
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "dates": [(start + timedelta(days=n)).isoformat() for n in range(PAST_DAYS + FUTURE_DAYS + 1)],
        "sourceErrors": errors + more_errors + metadata_errors,
        "restaurants": [
            {"unit": r["restaurant_unit"], "building": r["building_number"], "buildingName": r["building_name"],
             "floor": r["floor"], "weekdayHours": r["weekday_hours"], "saturdayHours": r["saturday_hours"],
             "holidayHours": r["holiday_hours"], "hoursStatus": r["hours_status"],
             "latitude": r["latitude"], "longitude": r["longitude"]}
            for r in directory
        ],
        "menus": menus,
    }


def _check() -> None:
    days = [f"2026-10-{d:02d}" for d in range(1, 21)]
    daily = [{"date": d, "unit": "U", "meal": "LUNCH", "name": "fixed", "priceWon": 1} for d in days]
    sometimes = [{"date": d, "unit": "V", "meal": "BREAKFAST", "name": "rare", "priceWon": 1} for d in days[:3]]
    out = fold_fixed(daily + sometimes)
    assert [m["date"] for m in out if m["name"] == "fixed"] == [None]
    assert sorted(m["date"] for m in out if m["name"] == "rare") == days[:3]
    only_few_days = [{"date": d, "unit": "W", "meal": "LUNCH", "name": "same", "priceWon": 1} for d in days[:8]]
    assert all(m["date"] for m in fold_fixed(daily + only_few_days) if m["name"] == "same")


if __name__ == "__main__":
    _check()
    out = Path(sys.argv[1])
    out.write_text(json.dumps(build(), ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size // 1024} KB)")
