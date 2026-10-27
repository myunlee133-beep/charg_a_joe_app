"""Orchestrate independent collection and durable, auditable exports."""
from __future__ import annotations

import csv
import json
import hashlib
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode

from .http import RateLimitedFetcher
from .parser import PageStructureError, parse_daily_table, parse_vet_week
from .sources import LOCATIONS, SOURCES
from .fixed import CATALOG_COLUMNS, FIXED_RESTAURANTS, fixed_item_rows, load_fixed_catalog
from .hours import extract_service_hours
from .directory import (GUIDE_URL, MAP_URL, make_directory, compare_siksha, parse_guide, parse_campus_map, registry_rows)

FIELDS = ("source", "source_date", "restaurant", "meal_type", "line_order", "kind",
          "raw_text", "name", "price_won", "no_meat_label", "price_ambiguous", "source_url", "restaurant_unit", "price_raw", "price_status")
ITEM_FIELDS = ("record_id", "source_date", "source", "building_number", "building_name",
               "restaurant", "meal_type", "menu_name", "price_won", "no_meat_label", "source_url", "price_variant", "data_origin", "price_status", "restaurant_unit", "price_raw")
ENTRY_FIELDS = ITEM_FIELDS + ("entry_kind", "price_known")


def daterange(start: date, days: int) -> list[date]:
    if not 1 <= days <= 31:
        raise ValueError("days must be 1..31 (maximum one month) to bound collection traffic")
    return [start + timedelta(days=n) for n in range(days)]


def _collect_one(source: str, day: date | None, fetcher: RateLimitedFetcher) -> list[dict]:
    endpoint = SOURCES[source]
    url = endpoint if day is None else f"{endpoint}?{urlencode({'date': day.isoformat()})}"
    html = fetcher.get(url)
    if source == "vet":
        assert day is not None
        rows = parse_vet_week(html, anchor=day)
    else:
        assert day is not None
        rows = parse_daily_table(html, day, source)
    return [{**row, "source_url": url} for row in rows]


def collect(*, start: date, days: int = 1, sources: tuple[str, ...] = ("snuco", "snudorm", "vet"),
            fetcher: RateLimitedFetcher | None = None, strict: bool = False) -> tuple[list[dict], list[dict]]:
    """Collect across sources; retain per-target errors rather than silently swallowing them."""
    dates = daterange(start, days)
    if not sources or any(s not in SOURCES for s in sources):
        raise ValueError(f"sources must be a nonempty subset of {tuple(SOURCES)}")
    fetcher = fetcher or RateLimitedFetcher()
    output: list[dict] = []
    errors: list[dict] = []
    for source in dict.fromkeys(sources):
        targets = [dates[0]] if source == "vet" else dates
        for day in targets:
            try:
                rows = _collect_one(source, day, fetcher)
                # Pages with valid structure but empty meal cells are not errors.
                output.extend(rows)
            except (Exception) as exc:
                issue = {"source": source, "date": day.isoformat(),
                         "error_type": type(exc).__name__, "message": str(exc)}
                errors.append(issue)
                if strict:
                    raise RuntimeError(f"Collection failed: {issue}") from exc
    # Vet page may include dates outside the requested window; filter strictly.
    allowed = {d.isoformat() for d in dates}
    output = [row for row in output if row["source_date"] in allowed]
    return output, errors


def _csv(path: Path, rows: list[dict], columns: tuple[str, ...]) -> None:
    # utf-8-sig supports Microsoft Excel without mangling Hangul; values safely escaped.
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            clean = {k: ("'" + v if isinstance(v, str) and v[:1] in ("=", "+", "-", "@") else v)
                     for k, v in row.items()}
            writer.writerow(clean)


def _unit_loc(unit: str, parent: str):
    registry = {r['restaurant_unit']:r for r in registry_rows()}
    entry = registry.get(unit)
    if entry:
        return entry['building_number'],entry['building_name']
    return LOCATIONS.get(parent,(None,None))


def flatten_items(observations: list[dict]) -> list[dict]:
    """Export only safely priced menu entries; no guesses or partial price reads."""
    seen=set();output=[]
    for row in observations:
        if row['kind']!='priced_item' or row['price_won'] is None: continue
        unit=row.get('restaurant_unit') or row['restaurant']
        loc=_unit_loc(unit,row['restaurant'])
        identity='|'.join(map(str,(row['source'],row['source_date'],unit,row['meal_type'],row['name'],row['price_won'])))
        key=hashlib.sha256(identity.encode()).hexdigest()[:20]
        if key in seen:continue
        seen.add(key)
        output.append({'record_id':key,'source_date':row['source_date'],'source':row['source'],
            'building_number':loc[0],'building_name':loc[1],'restaurant':row['restaurant'],
            'restaurant_unit':unit,'meal_type':row['meal_type'],'menu_name':row['name'],
            'price_won':row['price_won'],'no_meat_label':row['no_meat_label'],
            'source_url':row['source_url'],'price_variant':'','data_origin':'observed_page',
            'price_status':row.get('price_status','as_published'),'price_raw':row.get('price_raw','')})
    return output


def flatten_entries(observations: list[dict]) -> list[dict]:
    """Keep unpriced dishes and suspect raw prices for review, not just sale items."""
    result=[];seen=set()
    for row in observations:
        if row['kind'] not in ('priced_item','unpriced_text'): continue
        unit=row.get('restaurant_unit') or row['restaurant']
        loc=_unit_loc(unit,row['restaurant'])
        identity='|'.join(map(str,(row['source'],row['source_date'],unit,row['meal_type'],row['line_order'],row['name'])))
        key=hashlib.sha256(identity.encode()).hexdigest()[:20]
        if key in seen:continue
        seen.add(key)
        result.append({'record_id':key,'source_date':row['source_date'],'source':row['source'],
            'building_number':loc[0],'building_name':loc[1],'restaurant':row['restaurant'],
            'restaurant_unit':unit,'meal_type':row['meal_type'],'menu_name':row['name'],
            'price_won':row['price_won'],'no_meat_label':row['no_meat_label'],
            'source_url':row['source_url'],'entry_kind':row['kind'],
            'price_known':row['price_won'] is not None,'price_variant':'',
            'data_origin':'observed_page','price_status':row.get('price_status',''),
            'price_raw':row.get('price_raw','')})
    return result


def collect_metadata(fetcher=None) -> tuple[list[dict],list[dict]]:
    """Official dining guide + optional SNU campus map; failures are explicit."""
    fetcher=fetcher or RateLimitedFetcher()
    guide=None;coords=None;errors=[]
    for source,url in [('snuco_guide',GUIDE_URL),('campus_map',MAP_URL)]:
        try:
            html=fetcher.get(url)
            if source=='snuco_guide':guide=parse_guide(html)
            else: coords=parse_campus_map(html)
        except Exception as e:
            errors.append({'source':source,'date':'','error_type':type(e).__name__,'message':str(e)})
    return make_directory(guide,coords),errors

def summarize(rows: list[dict], errors: list[dict], *, started: date, days: int,
              sources: tuple[str, ...], restaurant_directory: list[dict] | None = None) -> dict:
    """Build the same run report without writing any CSV/JSON files."""
    use_fixed='snuco' in sources
    fixed_catalog=load_fixed_catalog() if use_fixed else []
    fixed_observed=[r for r in rows if r['source']=='snuco' and r['restaurant'] in FIXED_RESTAURANTS]
    dated_rows=[r for r in rows if not (use_fixed and r['source']=='snuco' and r['restaurant'] in FIXED_RESTAURANTS)]
    dynamic_items=flatten_items(dated_rows)
    static_items=fixed_item_rows(fixed_catalog)
    for item in static_items:
        item.setdefault('restaurant_unit',item['restaurant'])
        item.setdefault('price_raw','')
    static_priced=[r for r in static_items if r['price_won'] is not None and r['price_status'] in ('published_price','trailing_zero_corrected')]
    items=dynamic_items+static_priced
    entries=flatten_entries(dated_rows)+[{**r,'entry_kind':'fixed_catalog','price_known':r['price_won'] is not None} for r in static_items]
    directory_rows=restaurant_directory if restaurant_directory is not None else make_directory()
    report={'project':'Chajwo independent crawler v0.3.2','generated_at_utc':datetime.now(timezone.utc).isoformat(),
       'start':started.isoformat(),'days':days,'end':(started+timedelta(days=days-1)).isoformat(),
       'sources':list(sources),'observation_count':len(rows),'entry_count':len(entries),
       'priced_item_count':len(items),'dated_item_count':len(dynamic_items),
       'fixed_catalog_rows':len(static_items),
       'fixed_catalog_needs_review':sum(r['price_status']=='needs_review' for r in fixed_catalog),
       'fixed_page_observation_lines':len(fixed_observed),'restaurant_count':len(directory_rows),
       'guide_matched_units':sum(r['hours_status']=='official_guide' for r in directory_rows),
       'coordinates_matched_units':sum(r['latitude'] is not None for r in directory_rows),
       'price_autocorrections':sum(r.get('price_status')=='trailing_zero_corrected' for r in rows),
       'meal_hour_notice_count':len(extract_service_hours(rows)),
       'errors':len(errors),'by_source':dict(Counter(r['source'] for r in rows)),
       'unknown_locations':sorted({r['restaurant_unit'] for r in rows if not _unit_loc(r['restaurant_unit'],r['restaurant'])[0]}),
       'status':'partial_failure' if errors else 'completed'}
    return report


def export(rows: list[dict], errors: list[dict], directory: str | Path, *, started: date,
           days: int, sources: tuple[str,...], restaurant_directory: list[dict]|None=None) -> dict:
    path=Path(directory);path.mkdir(parents=True,exist_ok=True)
    use_fixed='snuco' in sources
    fixed_catalog=load_fixed_catalog() if use_fixed else []
    fixed_observed=[r for r in rows if r['source']=='snuco' and r['restaurant'] in FIXED_RESTAURANTS]
    dated_rows=[r for r in rows if not (use_fixed and r['source']=='snuco' and r['restaurant'] in FIXED_RESTAURANTS)]
    dynamic_items=flatten_items(dated_rows)
    static_items=fixed_item_rows(fixed_catalog)
    for item in static_items:
        item.setdefault('restaurant_unit',item['restaurant']);item.setdefault('price_raw','')
    static_priced=[r for r in static_items if r['price_won'] is not None and r['price_status'] in ('published_price','trailing_zero_corrected')]
    items=dynamic_items+static_priced
    entries=flatten_entries(dated_rows)+[{**r,'entry_kind':'fixed_catalog','price_known':r['price_won'] is not None} for r in static_items]
    directory_rows=restaurant_directory if restaurant_directory is not None else make_directory()
    _csv(path/'menu_lines.csv',rows,FIELDS)
    _csv(path/'menu_items.csv',items,ITEM_FIELDS)
    _csv(path/'menu_entries.csv',entries,ENTRY_FIELDS)
    directory_cols=('restaurant_unit','building_number','building_name','floor','registry_origin','parent',
       'menu_source','location_source','weekday_hours','saturday_hours','holiday_hours',
       'hours_source','hours_status','latitude','longitude','coordinates_source',
       'coordinates_precision','guide_location_raw')
    _csv(path/'restaurant_directory.csv',directory_rows,directory_cols)
    # Backward-compatible places file, now with all 33 known units including currently unposted units.
    places=[{'source':'registry','restaurant':r['restaurant_unit'], 'building_number':r['building_number'],
       'building_name':r['building_name'],'floor':r['floor'],'location_note':r['registry_origin'],
       'weekday_hours':r['weekday_hours'],'saturday_hours':r['saturday_hours'],
       'holiday_hours':r['holiday_hours'],'latitude':r['latitude'],'longitude':r['longitude']}
       for r in directory_rows]
    _csv(path/'locations.csv',places,('source','restaurant','building_number','building_name','floor',
       'location_note','weekday_hours','saturday_hours','holiday_hours','latitude','longitude'))
    _csv(path/'meal_service_hours.csv',extract_service_hours(rows),('source_date','restaurant_unit','meal_type','raw_notice','normalized_notice','source','source_url'))
    _csv(path/'siksha_seed_comparison.csv',compare_siksha(directory_rows),('restaurant_unit','building_number','comparison','note'))
    _csv(path/'fixed_menu_catalog.csv',fixed_catalog,CATALOG_COLUMNS)
    _csv(path/'fixed_menu_observed.csv',fixed_observed,FIELDS)
    (path/'raw_records.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
    (path/'errors.json').write_text(json.dumps(errors,ensure_ascii=False,indent=2),encoding='utf-8')
    report=summarize(rows,errors,started=started,days=days,sources=sources,restaurant_directory=directory_rows)
    (path/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    return report
