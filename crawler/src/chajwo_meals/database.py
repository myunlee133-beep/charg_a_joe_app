"""Persistent SQLite / PostgreSQL sync with per-date/source failure isolation.

A failed or unpopulated page NEVER deletes prior successful rows. A populated
successful date-source group is replaced transactionally, including changed
prices/removals; each run is audited. Configure an external PostgreSQL DB for
GitHub Actions, since Actions runners have ephemeral disks.
"""
from __future__ import annotations
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

SQLITE_DDL = '''
CREATE TABLE IF NOT EXISTS restaurants (
 name TEXT PRIMARY KEY, building_number TEXT, building_name TEXT, floor TEXT,
 latitude REAL, longitude REAL, weekday_hours TEXT, saturday_hours TEXT,
 holiday_hours TEXT, hours_source TEXT, hours_status TEXT, location_source TEXT,
 registry_origin TEXT, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS menu_entries (
 record_id TEXT PRIMARY KEY, source_date TEXT, source TEXT NOT NULL,
 restaurant TEXT NOT NULL, restaurant_unit TEXT NOT NULL, meal_type TEXT NOT NULL,
 menu_name TEXT NOT NULL, price_won INTEGER, source_url TEXT, data_origin TEXT NOT NULL,
 entry_kind TEXT, price_status TEXT, price_variant TEXT, raw_text TEXT,
 updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_meals_date_unit ON menu_entries(source_date, restaurant_unit);
CREATE INDEX IF NOT EXISTS idx_meals_source_date ON menu_entries(source,source_date);
CREATE TABLE IF NOT EXISTS meal_service_hours (
 source_date TEXT NOT NULL, restaurant_unit TEXT NOT NULL, meal_type TEXT NOT NULL,
 raw_notice TEXT NOT NULL, normalized_notice TEXT, source TEXT,
 source_url TEXT, updated_at TEXT NOT NULL,
 PRIMARY KEY(source_date, restaurant_unit, meal_type, raw_notice)
);
CREATE TABLE IF NOT EXISTS crawl_runs (
 id INTEGER PRIMARY KEY AUTOINCREMENT, executed_at TEXT NOT NULL,
 start_date TEXT NOT NULL, days INTEGER NOT NULL, status TEXT NOT NULL,
 error_count INTEGER NOT NULL, updated_scopes INTEGER NOT NULL, manifest_json TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS crawl_errors (
 id INTEGER PRIMARY KEY AUTOINCREMENT, executed_at TEXT NOT NULL,
 source TEXT, target_date TEXT, error_type TEXT, message TEXT
);
'''

POSTGRES_DDL = [
'''CREATE TABLE IF NOT EXISTS restaurants (
 name TEXT PRIMARY KEY, building_number TEXT, building_name TEXT, floor TEXT,
 latitude DOUBLE PRECISION, longitude DOUBLE PRECISION, weekday_hours TEXT,
 saturday_hours TEXT, holiday_hours TEXT, hours_source TEXT, hours_status TEXT,
 location_source TEXT, registry_origin TEXT, updated_at TEXT NOT NULL)''',
'''CREATE TABLE IF NOT EXISTS menu_entries (
 record_id TEXT PRIMARY KEY, source_date TEXT, source TEXT NOT NULL,
 restaurant TEXT NOT NULL, restaurant_unit TEXT NOT NULL, meal_type TEXT NOT NULL,
 menu_name TEXT NOT NULL, price_won INTEGER, source_url TEXT, data_origin TEXT NOT NULL,
 entry_kind TEXT, price_status TEXT, price_variant TEXT, raw_text TEXT,
 updated_at TEXT NOT NULL)''',
'CREATE INDEX IF NOT EXISTS idx_meals_date_unit ON menu_entries(source_date, restaurant_unit)',
'CREATE INDEX IF NOT EXISTS idx_meals_source_date ON menu_entries(source,source_date)',
'''CREATE TABLE IF NOT EXISTS meal_service_hours (
 source_date TEXT NOT NULL, restaurant_unit TEXT NOT NULL, meal_type TEXT NOT NULL,
 raw_notice TEXT NOT NULL, normalized_notice TEXT, source TEXT,source_url TEXT,updated_at TEXT NOT NULL,
 PRIMARY KEY(source_date, restaurant_unit, meal_type, raw_notice))''',
'''CREATE TABLE IF NOT EXISTS crawl_runs (
 id BIGSERIAL PRIMARY KEY, executed_at TEXT NOT NULL, start_date TEXT NOT NULL,
 days INTEGER NOT NULL, status TEXT NOT NULL, error_count INTEGER NOT NULL,
 updated_scopes INTEGER NOT NULL, manifest_json TEXT NOT NULL)''',
'''CREATE TABLE IF NOT EXISTS crawl_errors (
 id BIGSERIAL PRIMARY KEY, executed_at TEXT NOT NULL, source TEXT,
 target_date TEXT, error_type TEXT, message TEXT)''',
]


def connect(url: str):
    if url.startswith('sqlite:///'):
        path=Path(url[len('sqlite:///'):]);path.parent.mkdir(parents=True,exist_ok=True)
        conn=sqlite3.connect(path,timeout=30)
        conn.execute('PRAGMA busy_timeout=30000')
        return conn, False
    if url.startswith(('postgresql://','postgres://')):
        try:
            import psycopg
        except ImportError as exc:
            raise RuntimeError('PostgreSQL needs: pip install ".[postgres]"') from exc
        return psycopg.connect(url), True
    raise ValueError('DATABASE_URL must start with sqlite:/// or postgresql://')


def _do(cur, sql: str, params: tuple=(), postgres: bool=False):
    cur.execute(sql.replace('?', '%s') if postgres else sql, params)


def sync_db(url: str, *, entries: list[dict], directory: list[dict], errors: list[dict],
            started: str, days: int, manifest: dict, hour_rows: list[dict] | None=None) -> dict:
    """Commit results with an atomic transaction and preserve failed date scopes."""
    conn, pg = connect(url)
    now = datetime.now(timezone.utc).isoformat()
    by_scope={}
    for item in entries:
        if item['data_origin']!='observed_page':
            continue
        if not item.get('source_date'):
            continue
        key=(item['source'],item['source_date'])
        by_scope.setdefault(key,[]).append(item)
    failed={(e['source'],e['date']) for e in errors if e.get('date')}
    # A site may return 200 for unpublished future menus. Zero-entry pages
    # cannot be safely distinguished from unpublished/blocked pages.
    eligible={k:v for k,v in by_scope.items() if k not in failed and v}
    static=[r for r in entries if r['data_origin']=='fixed_catalog']
    sql_upsert_rest = '''INSERT INTO restaurants
    (name,building_number,building_name,floor,latitude,longitude,weekday_hours,saturday_hours,
     holiday_hours,hours_source,hours_status,location_source,registry_origin,updated_at)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(name) DO UPDATE SET
    building_number=excluded.building_number,building_name=excluded.building_name,
    floor=excluded.floor,
    latitude=COALESCE(excluded.latitude,restaurants.latitude),
    longitude=COALESCE(excluded.longitude,restaurants.longitude),
    weekday_hours=CASE WHEN excluded.hours_status='official_guide' THEN excluded.weekday_hours ELSE restaurants.weekday_hours END,
    saturday_hours=CASE WHEN excluded.hours_status='official_guide' THEN excluded.saturday_hours ELSE restaurants.saturday_hours END,
    holiday_hours=CASE WHEN excluded.hours_status='official_guide' THEN excluded.holiday_hours ELSE restaurants.holiday_hours END,
    hours_source=CASE WHEN excluded.hours_status='official_guide' THEN excluded.hours_source ELSE restaurants.hours_source END,
    hours_status=CASE WHEN excluded.hours_status='official_guide' THEN excluded.hours_status ELSE restaurants.hours_status END,
    location_source=excluded.location_source, registry_origin=excluded.registry_origin,
    updated_at=excluded.updated_at'''
    sql_upsert_meal = '''INSERT INTO menu_entries
    (record_id,source_date,source,restaurant,restaurant_unit,meal_type,menu_name,price_won,
     source_url,data_origin,entry_kind,price_status,price_variant,raw_text,updated_at)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(record_id) DO UPDATE SET
    source_date=excluded.source_date,source=excluded.source,restaurant=excluded.restaurant,
    restaurant_unit=excluded.restaurant_unit,meal_type=excluded.meal_type,
    menu_name=excluded.menu_name,price_won=excluded.price_won,source_url=excluded.source_url,
    data_origin=excluded.data_origin,entry_kind=excluded.entry_kind,price_status=excluded.price_status,
    price_variant=excluded.price_variant,raw_text=excluded.raw_text,updated_at=excluded.updated_at'''
    try:
        cur=conn.cursor()
        if pg:
            for stmt in POSTGRES_DDL: _do(cur,stmt,postgres=True)
        else: cur.executescript(SQLITE_DDL)
        for r in directory:
            args=(r['restaurant_unit'],r['building_number'],r['building_name'],r['floor'],
                  r.get('latitude'),r.get('longitude'),r['weekday_hours'],r['saturday_hours'],
                  r['holiday_hours'],r['hours_source'],r['hours_status'],r['location_source'],
                  r['registry_origin'],now)
            _do(cur,sql_upsert_rest,args,pg)
        def persist(r):
            args=(r['record_id'],r['source_date'] or None,r['source'],r['restaurant'],
                  r.get('restaurant_unit') or r['restaurant'],r['meal_type'],r['menu_name'],
                  r['price_won'],r.get('source_url'),r['data_origin'],r.get('entry_kind',''),
                  r.get('price_status',''),r.get('price_variant',''),r.get('raw_text',''),now)
            _do(cur,sql_upsert_meal,args,pg)
        # Fixed menu snapshot may be re-synced even if all web requests fail.
        for r in static: persist(r)
        if static:
            keys={r['record_id'] for r in static}
            _do(cur, 'SELECT record_id FROM menu_entries WHERE data_origin=?', ('fixed_catalog',),pg)
            for (previous,) in cur.fetchall():
                if previous not in keys:
                    _do(cur,'DELETE FROM menu_entries WHERE record_id=?',(previous,),pg)
        for (source,day),records in eligible.items():
            _do(cur,'DELETE FROM menu_entries WHERE source=? AND source_date=? AND data_origin=?',
                (source,day,'observed_page'),pg)
            for r in records: persist(r)
        for (source,day),records in eligible.items():
            # An observed hour line is authoritative only for its own date.
            _do(cur,'DELETE FROM meal_service_hours WHERE source_date=? AND source=?', (day,source),pg)
            for h in (hour_rows or []):
                if h['source_date']!=day or h['source']!=source:continue
                _do(cur,'''INSERT INTO meal_service_hours
                    (source_date,restaurant_unit,meal_type,raw_notice,normalized_notice,source,source_url,updated_at)
                    VALUES (?,?,?,?,?,?,?,?)''' ,
                    (day,h['restaurant_unit'],h['meal_type'],h['raw_notice'],
                     h['normalized_notice'],source,h['source_url'],now),pg)
        _do(cur,'INSERT INTO crawl_runs (executed_at,start_date,days,status,error_count,updated_scopes,manifest_json) VALUES (?,?,?,?,?,?,?)',
            (now,started,days,manifest['status'],len(errors),len(eligible),json.dumps(manifest,ensure_ascii=False)),pg)
        for e in errors:
            _do(cur,'INSERT INTO crawl_errors (executed_at,source,target_date,error_type,message) VALUES (?,?,?,?,?)',
                (now,e.get('source'),e.get('date'),e.get('error_type'),e.get('message')),pg)
        conn.commit()
    except Exception:
        conn.rollback();raise
    finally:
        conn.close()
    return {'updated_source_date_scopes':len(eligible),'skipped_failed_scopes':len(failed),
            'preserved_empty_or_unpublished_scopes': 'all empty results are retained in DB until a nonempty successful update',
            'restaurant_rows':len(directory),'fixed_entry_rows':len(static)}
