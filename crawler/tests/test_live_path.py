"""Live CLI control-flow tests. HTTP is mocked: no claims about real site reachability."""
import json
import sqlite3
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

from chajwo_meals.cli import main
from chajwo_meals.http import RateLimitedFetcher

FIX = Path(__file__).parent / "fixtures"


def _fake_pages(calls, outage=False, changed=False):
    def fetch(self, url):
        calls.append(url)
        if outage:
            raise ConnectionError('DNS failure: simulated external outage')
        if 'snuco.snu.ac.kr/foodmenu/' in url:
            name = 'snuco.html'
        elif 'snudorm.snu.ac.kr/foodmenu/' in url:
            name = 'snudorm.html'
        elif 'vet.snu.ac.kr/cafe_menu/' in url:
            name = 'vet.html'
        elif '/식당안내/' in url:
            name = 'guide_demo.html'
        elif 'map.snu.ac.kr/api/building.action' in url:
            name = 'campus_map_demo.json'
        else:
            raise AssertionError('Unexpected live request: ' + url)
        body = (FIX / name).read_text(encoding='utf8')
        if name in ('snuco.html', 'snudorm.html'):
            params = parse_qs(urlsplit(url).query)
            assert len(params['date']) == 1
            body = body.replace('2026-10-22', params['date'][0])
            if changed and name == 'snuco.html':
                body = body.replace('6,000원', '7,000원')
        return body
    return fetch


def _call(tmp_path, daycount):
    output = tmp_path / 'out'
    db = tmp_path / 'live.sqlite3'
    rc = main(['--live', '--start', '2026-10-22', '--days', str(daycount),
               '--write-db', '--database-url', 'sqlite:///' + str(db),
               '--output', str(output)])
    return rc, output, db


def test_full_30_day_live_pipeline_and_idempotent_db(monkeypatch, tmp_path):
    calls = []
    monkeypatch.setattr(RateLimitedFetcher, 'get', _fake_pages(calls))
    rc, output, db = _call(tmp_path, 30)
    assert rc == 0
    assert len(calls) == 63  # 30+30+1 + guide + map
    assert len([u for u in calls if 'foodmenu/' in u]) == 60
    manifest = json.loads((output / 'manifest.json').read_text(encoding='utf-8'))
    assert manifest['days'] == 30
    assert manifest['errors'] == 0
    assert manifest['restaurant_count'] == 33
    assert manifest['database_sync']['updated_source_date_scopes'] >= 60
    with sqlite3.connect(db) as conn:
        original = conn.execute('SELECT COUNT(*) FROM menu_entries').fetchone()[0]
        initial_runs = conn.execute('SELECT COUNT(*) FROM crawl_runs').fetchone()[0]
        assert initial_runs == 1
        assert original > 130
    # Rerunning must update rather than accumulate entries.
    monkeypatch.setattr(RateLimitedFetcher, 'get', _fake_pages([], changed=True))
    rc2, _, _ = _call(tmp_path, 30)
    assert rc2 == 0
    with sqlite3.connect(db) as conn:
        assert conn.execute('SELECT COUNT(*) FROM menu_entries').fetchone()[0] == original
        assert conn.execute('SELECT COUNT(*) FROM crawl_runs').fetchone()[0] == 2
        assert conn.execute('SELECT price_won FROM menu_entries WHERE menu_name=? AND data_origin=?',
                            ('호구세트', 'fixed_catalog')).fetchone()[0] == 8300


def test_live_network_outage_preserves_stored_menus(monkeypatch, tmp_path):
    monkeypatch.setattr(RateLimitedFetcher, 'get', _fake_pages([]))
    assert _call(tmp_path, 1)[0] == 0
    db = tmp_path / 'live.sqlite3'
    with sqlite3.connect(db) as conn:
        count = conn.execute('SELECT COUNT(*) FROM menu_entries').fetchone()[0]
        assert count > 0
    monkeypatch.setattr(RateLimitedFetcher, 'get', _fake_pages([], outage=True))
    rc, output, _ = _call(tmp_path, 1)
    assert rc == 2
    manifest = json.loads((output / 'manifest.json').read_text(encoding='utf-8'))
    assert manifest['errors'] == 5  # 3 sources + guide + map
    assert manifest['database_sync']['updated_source_date_scopes'] == 0
    with sqlite3.connect(db) as conn:
        assert conn.execute('SELECT COUNT(*) FROM menu_entries').fetchone()[0] == count
        assert conn.execute('SELECT COUNT(*) FROM crawl_errors').fetchone()[0] >= 5


def test_campus_map_euc_kr_decoded_safely():
    url = 'https://map.snu.ac.kr/api/building.action?page=1&rows=1000'
    content = '{"rows":[{"inst_kor_nm":"학생회관","vil_dong_nm":"63"}]}'.encode('euc-kr')
    class Response:
        def __init__(self, value):
            self.url = url
            self.content = value
            self.encoding = 'ISO-8859-1'
            self.apparent_encoding = 'ISO-8859-1'
        def raise_for_status(self):
            return None
        @property
        def text(self):
            return self.content.decode('latin-1')
    class Session:
        def __init__(self, val):
            self.val = val
        def get(self, *_args, **_kwargs):
            return Response(self.val)
    for body in (content, content.decode('euc-kr').encode('utf-8')):
        fetcher = RateLimitedFetcher(session=Session(body))
        assert '학생회관' in fetcher.get(url)


def test_notebook_live_isolated_from_demo():
    notebook = json.loads((Path(__file__).parents[1] / 'notebooks' / 'independent_meal_crawler.ipynb').read_text(encoding='utf-8'))
    setup = ''.join(notebook['cells'][3]['source'])
    assert "ZoneInfo('Asia/Seoul')" in setup
    assert "'notebook_live_v031'" in setup
    assert "'live_only.sqlite3'" in setup
    assert "with sqlite3.connect(DB_PATH)" in ''.join(notebook['cells'][12]['source'])
