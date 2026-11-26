"""Import verified official map photo URLs; bundle frequently visited buildings."""
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "ios/Chajajwo/Core/Resources"
ASSETS = ROOT / "ios/Chajajwo/Assets.xcassets"
BUNDLED = {"63", "301", "302", "62", "83", "64", "111", "109", "1", "58", "137-1", "104-1"}


def fetch(building):
    if not building["id"].startswith("snu-"):
        return None
    api = f'https://map.snu.ac.kr/api/building/{building["id"].split("-")[1]}.action?convinType=Y'
    try:
        r = requests.get(api, timeout=20); r.raise_for_status(); r.encoding = "euc-kr"
        info = r.json()["building"]
        if str(info.get("vil_dong_nm")) != str(building["number"]):
            return None
        path = info.get("prntmt_url") or ""
        if not path.startswith("/upload/") or ".." in path:
            return None
        url = "https://map.snu.ac.kr/api" + path
        record = {"buildingID": building["id"], "photoURL": url, "sourceURL": api,
                  "credit": "사진 · 서울대학교 공식 캠퍼스 지도", "checkedAt": "2026-11-26"}
        if building["number"] in BUNDLED:
            response = requests.get(url, timeout=20); response.raise_for_status()
            Image.open(io.BytesIO(response.content)).verify()
            name = "BuildingPhoto-" + building["id"]
            folder = ASSETS / (name + ".imageset"); folder.mkdir(exist_ok=True)
            (folder / "photo.jpg").write_bytes(response.content)
            (folder / "Contents.json").write_text(json.dumps({"images": [{"filename": "photo.jpg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
            record.update(assetName=name, sha256=hashlib.sha256(response.content).hexdigest())
        return record
    except (requests.RequestException, ValueError, KeyError, OSError) as error:
        print("Unavailable:", building["id"], type(error).__name__)
        return None


if __name__ == "__main__":
    buildings = json.loads((RES / "campus_buildings.json").read_text(encoding="utf-8"))
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        photos = [p for p in pool.map(fetch, buildings) if p]
    (RES / "building_photos.json").write_text(json.dumps(photos, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(photos)} photo mappings; bundled {sum('assetName' in p for p in photos)} original photographs")
