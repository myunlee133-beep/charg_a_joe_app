"""Tests of manually reviewed static menu snapshots and merger semantics."""
import csv
from datetime import date
from pathlib import Path
from urllib.parse import urlparse, parse_qs
import pytest
from chajwo_meals.fixed import FIXED_RESTAURANTS, load_fixed_catalog, fixed_item_rows
from chajwo_meals.parser import parse_daily_table
from chajwo_meals.pipeline import collect, export
from chajwo_meals.sources import LOCATIONS


FIXED_HTML = '''<html><input name="date" value="2026-10-22"/>
<table class="menu-table"><tbody>
<tr><td class="title">* 버거운버거 (878-9288)</td>
<td class="breakfast">버거운치킨버거 : 5,200원 / 7,700원</td>
<td class="lunch">버거운치킨버거 : 5,200원 / 7,700원</td>
<td class="dinner">버거운치킨버거 : 5,200원 / 7,700원</td></tr>
<tr><td class="title">* 공대간이식당 (889-8956)</td>
<td class="lunch">짜장면 : 4,500원<br>호구세트 : 8,3000원</td>
<td class="dinner">짜장면 : 4,500원</td></tr>
</tbody></table></html>'''

class MockFetcher:
    def get(self, url):
        target = parse_qs(urlparse(url).query).get("date", ["2026-10-22"])[0]
        return FIXED_HTML.replace("2026-10-22", target)


def test_fixed_names_are_canonical_from_official_asterisk():
    result = parse_daily_table(FIXED_HTML, date(2026, 10, 22), 'snuco')
    assert set(r['restaurant'] for r in result) == FIXED_RESTAURANTS
    assert len(result) == 6
    assert LOCATIONS['버거운버거'] == ('101동', '아시아연구소')
    assert LOCATIONS['공대간이식당'][0] == '30-2동'


def test_curated_catalog_complete_and_price_variants():
    data=load_fixed_catalog()
    assert len(data) == 136
    assert sum(r['restaurant']=='버거운버거' for r in data)==116
    assert sum(r['restaurant']=='공대간이식당' for r in data)==20
    burger=[r for r in data if r['menu_name']=='버거운치킨버거']
    assert [(r['price_variant'], r['price_won']) for r in burger]==[
        ('첫 번째 표기', 5200), ('두 번째 표기', 7700)]
    questionable=[r for r in data if r['menu_name']=='호구세트']
    assert questionable[0]['price_won'] == 8300
    assert questionable[0]['price_raw']=='8,3000원'
    assert questionable[0]['price_status']=='trailing_zero_corrected'
    assert all(r['source_url'].startswith('https://') for r in data)


def test_static_merges_without_date_duplication(tmp_path):
    collected, errors=collect(start=date(2026,10,22),days=2,sources=('snuco',),fetcher=MockFetcher())
    assert not errors
    report=export(collected, errors, tmp_path, started=date(2026,10,22), days=2, sources=('snuco',))
    assert report['fixed_catalog_rows']==136
    assert report['fixed_page_observation_lines']==12
    assert report['dated_item_count']==0
    with (tmp_path/'menu_items.csv').open(encoding='utf-8-sig') as f: items=list(csv.DictReader(f))
    with (tmp_path/'menu_entries.csv').open(encoding='utf-8-sig') as f: entries=list(csv.DictReader(f))
    with (tmp_path/'locations.csv').open(encoding='utf-8-sig') as f: locations=list(csv.DictReader(f))
    assert len(items)==134    # two price options still need human review
    assert len(entries)==136  # retains unresolved prices in entries/catalog
    assert all(i['source_date']=='' and i['meal_type']=='FIXED' for i in items)
    assert len({(i['restaurant'],i['menu_name'],i['price_variant']) for i in items})==134
    assert {p['restaurant']:p['building_number'] for p in locations}.items() >= {
        '버거운버거':'101동','공대간이식당':'30-2동'}.items()
    assert any(i['floor']=='1층 113호' for i in locations)
    assert (tmp_path/'fixed_menu_observed.csv').exists()


def test_static_fallback_even_without_observed_restaurant(tmp_path):
    report=export([], [{'source':'snuco','date':'2026-10-22',
                         'error_type':'Timeout','message':'site unavailable'}], tmp_path,
                  started=date(2026,10,22),days=1,sources=('snuco',))
    assert report['status']=='partial_failure'
    assert report['fixed_catalog_rows']==136
    assert report['restaurant_count']==33
    assert report['observation_count']==0


def test_no_static_for_other_source(tmp_path):
    report=export([],[],tmp_path,started=date(2026,10,22),days=1,sources=('vet',))
    assert report['fixed_catalog_rows']==0
    with (tmp_path/'fixed_menu_catalog.csv').open(encoding='utf-8-sig') as f:
        assert list(csv.DictReader(f)) == []


def test_bad_catalog_rejected(tmp_path):
    f=tmp_path/'bad.csv'
    f.write_text('restaurant,menu_name\n버거운버거,제육덮밥\n',encoding='utf-8')
    with pytest.raises(ValueError,match='missing required'):
        load_fixed_catalog(f)


def test_stable_catalog_keys():
    items=fixed_item_rows(load_fixed_catalog())
    assert len({r['record_id'] for r in items})==len(items)
    assert all(r['data_origin']=='fixed_catalog' and r['source_date']=='' for r in items)
