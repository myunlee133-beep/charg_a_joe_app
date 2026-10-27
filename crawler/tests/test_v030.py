"""Offline regression tests for own maintenance / daily re-collection requirements."""
import csv
import json
import sqlite3
from datetime import date, timedelta
from pathlib import Path
from chajwo_meals.database import sync_db
from chajwo_meals.directory import (parse_guide, make_directory, parse_campus_map, compare_siksha)
from chajwo_meals.hours import extract_service_hours
from chajwo_meals.parser import classify_line, parse_daily_table
from chajwo_meals.pipeline import collect, export, flatten_entries, daterange
from chajwo_meals.prices import parse_won
from chajwo_meals.fixed import fixed_item_rows, load_fixed_catalog

GUIDE = '''<html><table><tbody>
<tr><th>식당</th><th>위치</th><th>층별</th><th>규모</th><th>대상</th><th>평일</th><th>토요일</th><th>휴일</th></tr>
<tr><td>학생회관식당 (880-5543)</td><td>학생회관 (63동)</td><td>1층</td><td>380석</td><td>학생</td><td>08:00-10:00 11:00-14:30 17:00-19:00</td><td>11:30-14:00</td><td>휴관</td></tr>
<tr><td rowspan="2">자하연식당 (880-7888)</td><td rowspan="2">농협 (109동)</td><td>2층</td><td>268석</td><td>학생</td><td>11:30-14:00 17:00-18:30</td><td>휴관</td><td>휴관</td></tr>
<tr><td>3층</td><td>148석</td><td>교직원</td><td>11:30-14:00 예약</td><td>휴관</td><td>휴관</td></tr>
<tr><td>버거운버거 (878-9288)</td><td>아시아연구소(101동)</td><td>1층</td><td>72석</td><td>학생</td><td>09:00-20:00</td><td>09:00-20:00</td><td>09:00-20:00</td></tr>
<tr><td>프레퍼스 (070-8820-2161)</td><td>동원생활관(113동)</td><td>1층</td><td>108석</td><td>학생</td><td>08:00-20:00</td><td>11:00-19:00</td><td>11:00-19:00</td></tr>
</tbody></table></html>'''

HTML = '''<html><input name="date" value="2026-10-22"/><table class="menu-table"><tbody>
<tr><td class="title">3식당 (880-5545)</td><td class="lunch">제육볶음 : 6,000원<br>&lt;든든한끼샐러드코너&gt;<br>두부샐러드 : 8,000원</td></tr>
<tr><td class="title">220동식당 (887-1123)</td><td class="lunch">&lt;경성 돈카츠&gt;<br>돈카츠 : 6,900원<br>&lt;포포420&gt;<br>쌀국수 : 4,900원</td></tr>
<tr><td class="title">공대간이식당 (889-8956)</td><td class="lunch">호구세트 : 8,3000원<br>※ 운영시간 : 11 : 00 ~ 18 : 30</td></tr>
</tbody></table></html>'''


def test_ho_price_corrected():
    r=classify_line('호구세트 : 8,3000원')
    assert r['price_won']==8300 and r['price_status']=='trailing_zero_corrected'
    assert r['price_raw']=='8,3000원'


def test_valid_price_untouched():
    for amount in ['10,000','19,400','100,000']:
        price,status,corrected=parse_won(amount)
        assert status=='as_published' and corrected==amount


def test_invalid_grouping_without_trailing_zero_rejected():
    assert parse_won('8,3001')[0] is None
    assert parse_won('12,3456')[0] is None
    assert parse_won('1,2300')[0] == 1230


def test_dot_grouping_and_multiple_price():
    assert parse_won('5.900')[:2] == (5900,'dot_thousands_normalized')
    assert classify_line('버거 : 5,200원 / 7,700원')['price_won'] is None


def test_one_month_allowed():
    a=daterange(date(2026,10,22),30)
    assert len(a)==30 and a[-1]==date(2026,11,20)


def test_registry_and_siksha_missing_comparison():
    directory=make_directory()
    assert len(directory)==33
    pairs={r['restaurant_unit']:r for r in directory}
    assert pairs['버거운버거']['building_number']=='101동'
    assert pairs['프레퍼스']['building_number']=='113동'
    assert pairs['220동식당 포포420']['building_number']=='220동'
    audit=compare_siksha(directory)
    assert sum(a['comparison']=='in_siksha_v2_seed' for a in audit)==31
    assert {a['restaurant_unit'] for a in audit if a['comparison']!='in_siksha_v2_seed'}=={'버거운버거','프레퍼스'}


def test_official_guide_hours_and_floors():
    guide=parse_guide(GUIDE)
    directory=make_directory(guide=guide)
    lookup={r['restaurant_unit']:r for r in directory}
    assert lookup['버거운버거']['weekday_hours']=='09:00-20:00'
    assert lookup['프레퍼스']['saturday_hours']=='11:00-19:00'
    assert '예약' in lookup['자하연식당 3층']['weekday_hours']
    assert '17:00' in lookup['자하연식당 2층']['weekday_hours']
    assert lookup['학생회관식당']['floor']=='1층'


def test_map_coords_from_official_json():
    payload=json.dumps({'rows':[{'vil_dong_nm':'101','lat_val':'37.4633','lon_val':'126.9511'},
                                {'vil_dong_nm':'113','lat_val':'37.4555','lon_val':'126.9560'}]}).encode('euc-kr')
    directory=make_directory(coordinates=parse_campus_map(payload))
    burger=next(r for r in directory if r['restaurant_unit']=='버거운버거')
    assert burger['latitude']==37.4633
    assert burger['coordinates_precision']=='building_point'


def test_subunits_and_daily_service_hours():
    rows=parse_daily_table(HTML,date(2026,10,22),'snuco')
    assert {'3식당 일반','3식당 든든한끼샐러드코너','220동식당 경성 돈카츠','220동식당 포포420'} <= {r['restaurant_unit'] for r in rows}
    hours=extract_service_hours(rows)
    assert len(hours)==1 and '11:00-18:30' in hours[0]['normalized_notice']


def test_database_updates_price_and_preserves_error(tmp_path):
    path=tmp_path/'meals.sqlite3';db=f'sqlite:///{path}'
    directory=make_directory(parse_guide(GUIDE))
    observations=parse_daily_table(HTML,date(2026,10,22),'snuco')
    for row in observations: row['source_url']='https://snuco.snu.ac.kr/foodmenu/?date=2026-10-22'
    entries=flatten_entries(observations)+[{'entry_kind':'fixed_catalog',**r} for r in fixed_item_rows(load_fixed_catalog())]
    manifest={'status':'completed'}
    r1=sync_db(db,entries=entries,directory=directory,errors=[],started='2026-10-22',days=30,manifest=manifest,
               hour_rows=extract_service_hours(observations))
    assert r1['updated_source_date_scopes']==1
    with sqlite3.connect(path) as conn:
        assert conn.execute('SELECT price_won FROM menu_entries WHERE menu_name=? AND data_origin=?',('호구세트','observed_page')).fetchone()[0]==8300
        assert conn.execute('SELECT COUNT(*) FROM restaurants').fetchone()[0]==33
        assert conn.execute('SELECT COUNT(*) FROM meal_service_hours').fetchone()[0]==1
    # Successful refresh changes price in place and replaces stale date scope
    newer=[dict(x) for x in observations]
    for x in newer:
        if x['name']=='제육볶음': x['price_won']=7000
    entries2=flatten_entries(newer)
    sync_db(db,entries=entries2,directory=make_directory(),errors=[],started='2026-10-22',days=3,
            manifest={'status':'completed'},hour_rows=extract_service_hours(newer))
    with sqlite3.connect(path) as conn:
        assert conn.execute('SELECT price_won FROM menu_entries WHERE menu_name=? AND data_origin=?',('제육볶음','observed_page')).fetchone()[0]==7000
        assert '09:00-20:00' == conn.execute("SELECT weekday_hours FROM restaurants WHERE name='버거운버거'").fetchone()[0]
    # Failure must not erase previous successful data, neither should empty but HTTP-200 pages
    error=[{'source':'snuco','date':'2026-10-22','error_type':'Timeout','message':'offline'}]
    sync_db(db,entries=[],directory=make_directory(),errors=error,started='2026-10-22',days=30,
            manifest={'status':'partial_failure'})
    with sqlite3.connect(path) as conn:
        assert conn.execute('SELECT price_won FROM menu_entries WHERE menu_name=? AND data_origin=?',('제육볶음','observed_page')).fetchone()[0]==7000
        assert conn.execute('SELECT COUNT(*) FROM crawl_runs').fetchone()[0]==3
        assert conn.execute('SELECT COUNT(*) FROM crawl_errors').fetchone()[0]==1


def test_directory_export(tmp_path):
    manifest=export([],[],tmp_path,started=date(2026,10,22),days=30,sources=('snuco','snudorm','vet'),
                    restaurant_directory=make_directory(parse_guide(GUIDE)))
    assert manifest['restaurant_count']==33
    assert (tmp_path/'restaurant_directory.csv').exists()
    assert (tmp_path/'siksha_seed_comparison.csv').exists()
    with (tmp_path/'restaurant_directory.csv').open(encoding='utf-8-sig') as f:
        rows=list(csv.DictReader(f))
    assert sum(bool(r['weekday_hours']) for r in rows) >= 5


def test_buffet_priced_as_one_sale_unit():
    r=classify_line('<뷔페> 6,500원')
    assert r['price_won']==6500 and r['name']=='뷔페' and r['kind']=='priced_item'
