"""Storage isolation regression tests: mocked external responses, no live network."""
import csv
import json
import sqlite3
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

import pytest

from chajwo_meals import csv_runner, db_runner
from chajwo_meals.http import RateLimitedFetcher

FIX = Path(__file__).parent / 'fixtures'


def fake_http(calls, *, failed=False, changed=False):
    def getter(self, url):
        calls.append(url)
        if failed:
            raise ConnectionError('simulated network outage')
        if 'snuco.snu.ac.kr/foodmenu/' in url:
            name='snuco.html'
        elif 'snudorm.snu.ac.kr/foodmenu/' in url:
            name='snudorm.html'
        elif 'vet.snu.ac.kr/cafe_menu/' in url:
            name='vet.html'
        elif '/식당안내/' in url:
            name='guide_demo.html'
        elif 'map.snu.ac.kr/api/building.action' in url:
            name='campus_map_demo.json'
        else:
            raise AssertionError(f'Unexpected URL: {url}')
        data=(FIX/name).read_text(encoding='utf-8')
        if name in ('snuco.html', 'snudorm.html'):
            day=parse_qs(urlsplit(url).query)['date'][0]
            data=data.replace('2026-10-22',day)
            if changed and name == 'snuco.html':
                data=data.replace('6,000원','7,000원')
        return data
    return getter


def test_csv_only_exports_files_and_does_not_touch_database(monkeypatch,tmp_path):
    calls=[]
    monkeypatch.setattr(RateLimitedFetcher,'get',fake_http(calls))
    db=tmp_path/'should_not_exist.sqlite3'
    monkeypatch.setenv('DATABASE_URL',f'sqlite:///{db}')
    output=tmp_path/'csv_export'
    code=csv_runner.main(['--live','--start','2026-10-22','--days','1','--output',str(output)])
    assert code==0 and len(calls)==5
    assert not db.exists()
    manifest=json.loads((output/'manifest.json').read_text(encoding='utf-8'))
    assert manifest['storage']=='csv' and manifest['errors']==0
    assert manifest['restaurant_count']==33
    assert (output/'menu_items.csv').exists()
    assert (output/'restaurant_directory.csv').exists()
    assert (output/'meal_service_hours.csv').exists()
    with (output/'menu_entries.csv').open(encoding='utf-8-sig',newline='') as f:
        rows=list(csv.DictReader(f))
    assert any(row['menu_name']=='호구세트' and row['price_won']=='8300' for row in rows)


def test_db_only_writes_db_without_any_file_exports(monkeypatch,tmp_path):
    calls=[]
    monkeypatch.setattr(RateLimitedFetcher,'get',fake_http(calls))
    db=tmp_path/'application.sqlite3'
    output=tmp_path/'must_not_be_created'
    args=['--live','--start','2026-10-22','--days','1','--database-url',f'sqlite:///{db}',
          '--output',str(output)]
    assert db_runner.main(args)==0
    assert len(calls)==5
    assert not output.exists()
    assert db.is_file()
    with sqlite3.connect(db) as conn:
        assert conn.execute('SELECT COUNT(*) FROM restaurants').fetchone()[0]==33
        first=conn.execute('SELECT COUNT(*) FROM menu_entries').fetchone()[0]
        assert first>=136
        assert conn.execute("SELECT price_won FROM menu_entries WHERE menu_name='호구세트' AND data_origin='fixed_catalog'").fetchone()[0]==8300
        assert conn.execute('SELECT COUNT(*) FROM crawl_runs').fetchone()[0]==1
        assert conn.execute('SELECT COUNT(*) FROM crawl_errors').fetchone()[0]==0
    monkeypatch.setattr(RateLimitedFetcher,'get',fake_http([],changed=True))
    assert db_runner.main(args)==0
    with sqlite3.connect(db) as conn:
        assert conn.execute('SELECT COUNT(*) FROM menu_entries').fetchone()[0]==first
        assert conn.execute('SELECT COUNT(*) FROM crawl_runs').fetchone()[0]==2
        assert conn.execute("SELECT price_won FROM menu_entries WHERE menu_name='호구세트' AND data_origin='fixed_catalog'").fetchone()[0]==8300
    assert not output.exists()


def test_db_mode_preserves_good_data_on_network_error(monkeypatch,tmp_path):
    db=tmp_path/'test.sqlite3'
    args=['--live','--start','2026-10-22','--days','1','--database-url',f'sqlite:///{db}']
    monkeypatch.setattr(RateLimitedFetcher,'get',fake_http([]))
    assert db_runner.main(args)==0
    with sqlite3.connect(db) as conn:
        initial=conn.execute("SELECT COUNT(*) FROM menu_entries WHERE data_origin='observed_page'").fetchone()[0]
        assert initial>0
    monkeypatch.setattr(RateLimitedFetcher,'get',fake_http([],failed=True))
    assert db_runner.main(args)==2
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT COUNT(*) FROM menu_entries WHERE data_origin='observed_page'").fetchone()[0]==initial
        assert conn.execute('SELECT COUNT(*) FROM crawl_errors').fetchone()[0]==5


def test_csv_runner_rejects_database_write_flag(capsys):
    with pytest.raises(SystemExit):
        csv_runner.main(['--live','--write-db','--database-url','sqlite:///unsafe.sqlite3'])
    assert 'cannot use --write-db' in capsys.readouterr().err


def test_db_runner_rejects_non_db_storage():
    with pytest.raises(SystemExit):
        db_runner.main(['--live','--storage','both'])


def test_db_runner_requires_database_url(monkeypatch):
    monkeypatch.delenv('DATABASE_URL',raising=False)
    with pytest.raises(SystemExit):
        db_runner.main(['--live'])


def test_csv_and_db_share_identical_menu_record_identifiers(monkeypatch,tmp_path):
    monkeypatch.setattr(RateLimitedFetcher,'get',fake_http([]))
    out=tmp_path/'csv'
    assert csv_runner.main(['--live','--start','2026-10-22','--days','1','--output',str(out)])==0
    with (out/'menu_entries.csv').open(encoding='utf-8-sig',newline='') as handle:
        csv_ids={r['record_id'] for r in csv.DictReader(handle)}
    db=tmp_path/'app.sqlite3'
    assert db_runner.main(['--live','--start','2026-10-22','--days','1','--database-url',f'sqlite:///{db}'])==0
    with sqlite3.connect(db) as conn:
        db_ids={r[0] for r in conn.execute('SELECT record_id FROM menu_entries')}
    assert csv_ids==db_ids


def test_recurring_action_workflows_use_db_only():
    root=Path(__file__).parents[1]
    for file in (root/'.github/workflows/full-month.yml',root/'.github/workflows/same-day-refresh.yml'):
        content=file.read_text(encoding='utf-8')
        assert 'python -m chajwo_meals.db_runner --live' in content
        assert '--write-db' not in content
        assert 'upload-artifact' not in content
