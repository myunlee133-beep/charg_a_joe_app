"""Independent restaurant inventory, official hours and optional campus-map locations.

No Siksha imports or runtime requests. Siksha V2's published seed is an audit
baseline ONLY; locations and hours are sourced from SNUCO's official guide.
"""
from __future__ import annotations
import csv
import json
import re
from pathlib import Path
from bs4 import BeautifulSoup

REGISTRY_PATH = Path(__file__).parent / 'data' / 'restaurant_registry.csv'
GUIDE_URL = 'https://snuco.snu.ac.kr/식당안내/'
MAP_URL = 'https://map.snu.ac.kr/api/building.action?page=1&rows=1000'


def registry_rows() -> list[dict]:
    with REGISTRY_PATH.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def norm(s: str) -> str:
    return re.sub(r'\s+', ' ', s.replace('\xa0', ' ')).strip()


def normalize_site_name(s: str) -> str:
    s = re.sub(r'\(?\s*(?:\d{2,4}-)?\d{3,4}-\d{4}\s*\)?', '', norm(s))
    s = re.sub(r'^\*\s*', '', s)
    return norm(s)


def _expanded_rows(table):
    """Flatten an HTML table with rowspan / colspan for the SNUCO guide."""
    carry = {}
    for tr in table.find_all('tr'):
        cells = []
        col = 0
        def take_carry():
            nonlocal col
            while col in carry:
                txt, remain = carry[col]
                cells.append(txt)
                if remain <= 1:
                    del carry[col]
                else:
                    carry[col] = (txt, remain-1)
                col += 1
        take_carry()
        for td in tr.find_all(['td', 'th'], recursive=False):
            take_carry()
            txt = norm(td.get_text(' ', strip=True))
            span = int(td.get('colspan', 1))
            rows = int(td.get('rowspan', 1))
            for _ in range(span):
                cells.append(txt)
                if rows > 1:
                    carry[col] = (txt, rows-1)
                col += 1
        take_carry()
        yield cells


def parse_guide(html: str) -> list[dict]:
    """Parse official dining-guide metadata, retaining displayed unmodified hours."""
    soup = BeautifulSoup(html, 'html.parser')
    parsed = []
    for table in soup.find_all('table'):
        table_rows = list(_expanded_rows(table))
        if not any('학생회관식당' in ' '.join(c) for c in table_rows):
            continue
        for c in table_rows:
            if len(c) < 8:
                continue
            name = normalize_site_name(c[0])
            if not name or any(x in name for x in ('식당안내', '운영안내', '운영시간', '평일', '위치')):
                continue
            building_m = re.search(r'(?<!\d)(\d{1,3}(?:-\d+)?)\s*동', c[1])
            if not building_m:
                continue
            parsed.append({
                'restaurant': name,
                'building_number': building_m.group(1) + '동',
                'building_name_raw': c[1],
                'floor_raw': c[2],
                'weekday_hours': c[-3],
                'saturday_hours': c[-2],
                'holiday_hours': c[-1],
                'hours_source': GUIDE_URL,
            })
        break
    if not parsed:
        raise ValueError('SNUCO dining guide: table or restaurant rows not found')
    return parsed


def guide_parent(unit: str) -> str | None:
    if unit.startswith('3식당 '): return '3식당'
    if unit.startswith('4층 푸드코드 '): return '75-1동 4층 푸드코트'
    if unit.startswith('두레미담 '): return '두레미담'
    if unit.startswith('301동 ') or unit.startswith('301동식당 ') or unit == '카페 301': return '301동식당'
    if unit.startswith('220동식당 '): return '220동식당'
    if unit.startswith('예술계식당 '): return '예술계식당'
    if unit.startswith('자하연식당 '): return '자하연식당'
    if unit == '생협기숙사': return '기숙사식당'
    if unit == '아워홈': return '아워홈(901동)'
    return unit


def _guide_match(unit: dict, guide: list[dict]) -> dict | None:
    name = guide_parent(unit['restaurant_unit'])
    candidate = [r for r in guide if r['restaurant'] == name and r['building_number'] == unit['building_number']]
    if not candidate:
        candidate = [r for r in guide if r['building_number'] == unit['building_number'] and r['restaurant'] == name]
    if not candidate:
        return None
    floor = unit.get('floor', '')
    exact = [r for r in candidate if floor and (floor.replace(' ', '') in r['floor_raw'].replace(' ', '') or r['floor_raw'].replace(' ', '') in floor.replace(' ', ''))]
    # 301동 basement and first-floor staff can coexist: do not mix hours.
    return exact[0] if exact else (candidate[0] if len(candidate) == 1 or not floor else None)


def _row_coords(r: dict) -> tuple[float | None, float | None]:
    lat = r.get('lat_val') or r.get('latitude')
    lng = r.get('lon_val') or r.get('longitude')
    try:
        latf, lngf = float(lat), float(lng)
        return (latf, lngf) if 37.3 < latf < 37.6 and 126.7 < lngf < 127.1 else (None, None)
    except (TypeError, ValueError):
        return None, None


def parse_campus_map(raw: str | bytes) -> dict:
    if isinstance(raw, bytes):
        raw = raw.decode('euc-kr')
    js = json.loads(raw)
    if not isinstance(js, dict) or not isinstance(js.get('rows'), list):
        raise ValueError('Campus map: no rows list')
    found = {}
    for row in js['rows']:
        number = str(row.get('vil_dong_nm', '')).strip()
        if number and not number.endswith('동'): number += '동'
        xy = _row_coords(row)
        if number and all(x is not None for x in xy):
            found[number] = {'latitude':xy[0], 'longitude':xy[1],
                             'coordinates_source':MAP_URL, 'coordinates_precision':'building_point'}
    if not found:
        raise ValueError('Campus map: no valid coordinates')
    return found


# 901동은 학교 캠퍼스 지도에 좌표가 없고, 919동은 생협기숙사(세븐일레븐 건물) 위치와 약 50m 어긋난다.
# 카카오맵 위성지도에서 903/906/921/922/925동 기준점으로 보정한 값(오차 약 10m).
COORDINATE_OVERRIDES = {
    '901동': {'latitude': 37.46205, 'longitude': 126.95781},
    '919동': {'latitude': 37.46346, 'longitude': 126.95848},
}


def make_directory(guide: list[dict] | None = None, coordinates: dict | None = None) -> list[dict]:
    output = []
    for unit in registry_rows():
        match = _guide_match(unit, guide or [])
        loc = (coordinates or {}).get(unit['building_number'], {})
        override = COORDINATE_OVERRIDES.get(unit['building_number'])
        if override:
            loc = {**override, 'coordinates_source': 'manual_kakao_satellite', 'coordinates_precision': 'building_point'}
        output.append({**unit,
            'weekday_hours':match['weekday_hours'] if match else '',
            'saturday_hours':match['saturday_hours'] if match else '',
            'holiday_hours':match['holiday_hours'] if match else '',
            'hours_source':match['hours_source'] if match else '',
            'hours_status':'official_guide' if match else 'unknown',
            'latitude':loc.get('latitude'), 'longitude':loc.get('longitude'),
            'coordinates_source':loc.get('coordinates_source', ''),
            'coordinates_precision':loc.get('coordinates_precision', ''),
            'guide_location_raw':match['building_name_raw'] if match else '',
        })
    return output


def compare_siksha(directory: list[dict]) -> list[dict]:
    return [{'restaurant_unit':r['restaurant_unit'], 'building_number':r['building_number'],
             'comparison': ('in_siksha_v2_seed' if r['registry_origin']=='siksha_v2_seed'
                            else 'not_in_siksha_v2_seed_added_from_official_guide'),
             'note':'Comparison is with migration seed, NOT a current live Siksha list.'}
            for r in directory]
