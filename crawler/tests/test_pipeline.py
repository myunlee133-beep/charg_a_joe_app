import csv
import json
from datetime import date
from pathlib import Path
from unittest.mock import Mock
import pytest
from chajwo_meals.cli import main
from chajwo_meals.http import RateLimitedFetcher
from chajwo_meals.pipeline import collect, export, flatten_items, daterange
from chajwo_meals.parser import PageStructureError

FIXTURES = Path(__file__).parent / 'fixtures'


class MockFetcher:
    def __init__(self, failures=()):
        self.requests = []
        self.failures = failures

    def get(self, url):
        self.requests.append(url)
        if any(x in url for x in self.failures):
            raise RuntimeError('sample failure')
        if 'snuco.' in url:
            return (FIXTURES / 'snuco.html').read_text(encoding='utf8')
        if 'snudorm.' in url:
            return (FIXTURES / 'snudorm.html').read_text(encoding='utf8')
        if 'vet.' in url:
            return (FIXTURES / 'vet.html').read_text(encoding='utf8')
        raise ValueError(url)


def test_mock_collection_all():
    mock = MockFetcher()
    rows, errors = collect(start=date(2026,10,22), days=1, fetcher=mock)
    assert not errors
    assert len(mock.requests) == 3
    assert sum(r['source']=='vet' for r in rows) == 1  # only Oct 22
    assert sum(r['source']=='snuco' for r in rows) == 12


def test_vet_once_across_multiple_days():
    mock = MockFetcher()
    rows, errors = collect(start=date(2026,10,22), days=2, sources=('vet',), fetcher=mock)
    assert not errors
    assert len(mock.requests) == 1
    assert {r['source_date'] for r in rows} == {'2026-10-22', '2026-10-23'}


def test_partial_failure_is_explicit():
    mock = MockFetcher(failures=('snudorm.',))
    rows, errors = collect(start=date(2026,10,22), fetcher=mock)
    assert len(errors) == 1
    assert errors[0]['source'] == 'snudorm'
    assert any(r['source'] == 'snuco' for r in rows)


def test_strict_failure_raises():
    with pytest.raises(RuntimeError):
        collect(start=date(2026,10,22), sources=('snudorm',),
                fetcher=MockFetcher(failures=('snudorm.',)), strict=True)


def test_export_files_and_stable_keys(tmp_path):
    rows, errors = collect(start=date(2026,10,22), fetcher=MockFetcher())
    manifest = export(rows, errors, tmp_path, started=date(2026,10,22), days=1,
                      sources=('snuco','snudorm','vet'))
    assert manifest['status'] == 'completed'
    assert manifest['priced_item_count'] > 0
    assert (tmp_path / 'locations.csv').exists()
    assert json.loads((tmp_path/'manifest.json').read_text(encoding='utf8'))['errors'] == 0
    with (tmp_path/'menu_items.csv').open(encoding='utf-8-sig') as file:
        data = list(csv.DictReader(file))
    assert data[0]['record_id'] == flatten_items(rows)[0]['record_id']
    assert not any(x['menu_name'] == '잡곡밥' for x in data)
    assert any(x['building_number'] == '63동' for x in data)


def test_unknown_restaurant_kept():
    obs, err = collect(start=date(2026,10,22), sources=('snuco',), fetcher=MockFetcher())
    x = dict(obs[0], restaurant='새로운 식당', name='미역국', restaurant_unit='새로운 식당', kind='priced_item', price_won=3000)
    items = flatten_items([x])
    assert items[0]['building_number'] is None


def test_duplicate_priced_items_collapsed():
    obs, _ = collect(start=date(2026,10,22), sources=('snuco',), fetcher=MockFetcher())
    assert len(flatten_items(obs + obs)) == len(flatten_items(obs))


def test_days_limit():
    with pytest.raises(ValueError):
        daterange(date.today(), 32)
    assert len(daterange(date.today(), 30)) == 30


def test_unknown_sources():
    with pytest.raises(ValueError):
        collect(start=date.today(), sources=('what',), fetcher=MockFetcher())


def test_http_only_https():
    with pytest.raises(ValueError):
        RateLimitedFetcher().get('http://example.com')


def test_http_refuses_too_fast():
    with pytest.raises(ValueError):
        RateLimitedFetcher(min_interval=0.01)


def test_cli_requires_explicit_live():
    with pytest.raises(SystemExit) as e:
        main(['--start','2026-10-22'])
    assert e.value.code == 2
