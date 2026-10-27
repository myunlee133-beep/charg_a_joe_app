from datetime import date
from pathlib import Path
import pytest
from chajwo_meals.parser import (PageStructureError, _vet_date, cell_lines,
                                  classify_line, parse_daily_table, parse_vet_week)
from bs4 import BeautifulSoup

FIXTURES = Path(__file__).parent / 'fixtures'


def sample(name):
    return (FIXTURES / f'{name}.html').read_text(encoding='utf-8')


def test_snuco_rows():
    obs = parse_daily_table(sample('snuco'), date(2026, 10, 22), 'snuco')
    assert len(obs) == 12
    assert {x['restaurant'] for x in obs} == {'학생회관식당', '두레미담'}
    assert [x['price_won'] for x in obs if x['name'] == '버섯스크램블에그'] == [3000]
    assert any(x['no_meat_label'] is True and x['price_won'] == 3000 for x in obs)
    assert any(x['kind'] == 'section' for x in obs)
    assert any(x['kind'] == 'unpriced_text' and x['name'] == '잡곡밥' for x in obs)


def test_dormitory_rows():
    obs = parse_daily_table(sample('snudorm'), date(2026, 10, 22), 'snudorm')
    assert {x['restaurant'] for x in obs} == {'아워홈(901동)', '생협기숙사(919동)'}
    assert any(x['meal_type'] == 'DINNER' and x['price_won'] == 6000 for x in obs)


def test_vet_week_date_and_unpriced():
    obs = parse_vet_week(sample('vet'), anchor=date(2026,10,22))
    assert len(obs) == 5
    assert obs[-2]['source_date'] == '2026-10-22'
    assert all(x['price_won'] is None for x in obs)
    assert all(x['restaurant'] == '수의대식당' for x in obs)


def test_vet_unrelated_table_first():
    html = '<table><tr><td>x</td></tr></table>' + sample('vet')
    assert len(parse_vet_week(html, anchor=date(2026,10,22))) == 5


def test_vet_no_table():
    with pytest.raises(PageStructureError):
        parse_vet_week('<html>로그인</html>', anchor=date(2026,10,22))


def test_vet_stale_rejected():
    with pytest.raises(PageStructureError):
        parse_vet_week(sample('vet'), anchor=date(2026,12,22))


def test_invalid_weekday_vet():
    assert _vet_date('10. 22(금)', date(2026,10,22)) is None


def test_missing_menu_table():
    with pytest.raises(PageStructureError):
        parse_daily_table('<h1>접근 차단</h1>', date(2026,10,22), 'snuco')


def test_wrong_page_date():
    with pytest.raises(PageStructureError):
        parse_daily_table(sample('snuco'), date(2026,10,21), 'snuco')


def test_wrong_source():
    with pytest.raises(ValueError):
        parse_daily_table(sample('snuco'), date(2026,10,22), 'foo')


@pytest.mark.parametrize('text,expected', [
    ('비빔밥 : 6,000원', ('priced_item', 6000)),
    ('순두부찌개 : 6000원', ('priced_item', 6000)),
    ('※ 운영시간 : 11:00~14:30', ('notice', None)),
    ('그린샐러드', ('unpriced_text', None)),
    ('<주문식 메뉴>', ('section', None)),
    ('메뉴 : 6,000원 / 8,000원', ('unpriced_text', None)),
])
def test_price_classification(text, expected):
    row = classify_line(text)
    assert (row['kind'], row['price_won']) == expected


def test_line_breaks_with_markup():
    cell = BeautifulSoup('<td>잡곡밥<br><span>된장찌개</span><p>김치</p></td>', 'html.parser').td
    assert cell_lines(cell) == ['잡곡밥', '된장찌개', '김치']
