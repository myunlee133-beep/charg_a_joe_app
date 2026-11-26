"""Validate offline joins, provenance and the actual bundled menu photos."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "ios/Chajajwo/Core/Resources"
ASSETS = ROOT / "ios/Chajajwo/Assets.xcassets"


def read(name):
    return json.loads((RESOURCES / (name + ".json")).read_text(encoding="utf-8"))


def main():
    buildings = read("campus_buildings")
    labs = read("research_labs")
    venues = read("campus_venues")["venues"]
    assert len(buildings) == len({b["id"] for b in buildings}) == 251
    assert sum(len(b["details"]["facilities"]) for b in buildings) == 646
    numbers = {b["number"] for b in buildings}
    assert len(labs["labs"]) == 32 and len(venues) == 7
    assert all(l["buildingNumber"] in numbers for l in labs["labs"])
    assert all(v["buildingNumber"] in numbers for v in venues)
    assert all(l["buildingNumber"] not in numbers for l in labs["unmappedLabs"])
    assert all(l["professor"] and l["topics"] and l["url"].startswith("https://cse.snu.ac.kr/") for l in labs["labs"])
    photo_paths = set()
    for venue in venues:
        assert venue["sourceURL"].startswith("https://") and venue["checkedAt"]
        for record in [venue] + venue["menus"]:
            path = record.get("photoAsset")
            if not path:
                continue
            assert path.startswith("menu_photos/") and ".." not in path
            assert record.get("photoSourceURL", "").startswith("https://")
            assert record.get("photoCredit")
            filename = Path(path).name
            folder = ASSETS / ("PlaceMenu-" + Path(path).stem + ".imageset")
            contents = json.loads((folder / "Contents.json").read_text())
            assert contents["images"][0]["filename"] == filename
            assert (folder / filename).stat().st_size > 0
            photo_paths.add(folder / filename)
        assert all(m["priceWon"] is None for m in venue["menus"])
    assert len(photo_paths) == 6
    manifest = json.loads((ROOT / "docs/menu-photo-sources.json").read_text(encoding="utf-8"))
    for source in manifest["photos"]:
        photo = ASSETS / ("PlaceMenu-" + Path(source["asset"]).stem + ".imageset") / Path(source["asset"]).name
        assert hashlib.sha256(photo.read_bytes()).hexdigest() == source["sha256"]
    print(f"Validated {len(buildings)} buildings, 646 facilities, 32 labs, 7 venues, {len(photo_paths)} official photos.")
    for photo in sorted(photo_paths):
        print(f"{photo.name}: {hashlib.sha256(photo.read_bytes()).hexdigest()}")
    building_photos = read("building_photos")
    ids = {b["id"] for b in buildings}
    assert len(building_photos) > 200
    for record in building_photos:
        assert record["buildingID"] in ids
        assert record["photoURL"].startswith("https://map.snu.ac.kr/api/upload/")
        if record.get("assetName"):
            photo = ASSETS / (record["assetName"] + ".imageset") / "photo.jpg"
            assert hashlib.sha256(photo.read_bytes()).hexdigest() == record["sha256"]
    print(f"Validated {len(building_photos)} official building photo mappings and their bundled image hashes.")


if __name__ == "__main__":
    main()
