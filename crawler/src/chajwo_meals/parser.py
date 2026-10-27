"""Parse public dining table HTML into loss-preserving normalized observations.

This source code was independently written for Chajwo. It does not import or
execute code from Siksha. Site HTML may change; parsing then fails loudly.
"""
from __future__ import annotations

import re
from datetime import date, datetime, timedelta
from bs4 import BeautifulSoup, Tag

MEAL_NAMES = {"breakfast": "BREAKFAST", "lunch": "LUNCH", "dinner": "DINNER"}
PRICE_RE = re.compile(r"(?<!\d)(\d{1,3}(?:,\d{3})+|\d{4,6}|\d{1,3})\s*원")
PHONE_RE = re.compile(r"\s*\((?:0\d{1,2}-)?\d{3,4}-\d{4}\)\s*$")
VET_DAY_RE = re.compile(r"(?<!\d)(\d{1,2})\s*\.\s*(\d{1,2})\s*\(([월화수목금토일])\)")
WEEKDAY = dict(zip("월화수목금토일", range(7)))


class PageStructureError(ValueError):
    """Known page layout is absent, date mismatched, or content stale."""


def normalized(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("\xa0", " ")).strip()


def cell_lines(cell: Tag) -> list[str]:
    """Preserve explicit HTML line breaks, including text surrounded by tags."""
    fragment = BeautifulSoup(str(cell), "html.parser")
    for tag in fragment.find_all("br"):
        tag.replace_with("\n")
    for tag in fragment.find_all(["p", "div", "li"]):
        tag.insert_before("\n")
        tag.insert_after("\n")
    return [clean for part in fragment.get_text().splitlines() if (clean := normalized(part))]


from .prices import parse_price_text, TOKEN


def classify_line(text: str) -> dict:
    """Parse a sale price conservatively and retain the original text."""
    line = normalized(text)
    is_notice = (line.startswith(("※", "*운영", "운영시간")) or "예약문의" in line or
                 "혼잡시간" in line or line in {"휴무", "미운영", "운영 종료", "휴점", "준비중"})
    tail = re.sub(r"^<[^>]+>", "", line).strip() if line.startswith("<") else None
    heading = tail is not None and (not tail or bool(re.fullmatch(r"(?::\s*)?\d[\d,.]*\s*원", tail)))
    price, price_status, price_raw, ambiguous = parse_price_text(line)
    if is_notice:
        kind = "notice"; price = None
    elif heading and price is not None and re.search(r'<\s*(?:셀프)?뷔페[^>]*>', line):
        kind = 'priced_item'
    elif heading:
        kind = "section"
    elif price is not None:
        kind = "priced_item"
    else:
        kind = "unpriced_text"
    name = TOKEN.sub('', line).rstrip(' :：-·').strip() if kind == 'priced_item' else line
    if kind == 'priced_item' and heading and '뷔페' in line:
        name = re.search(r'<\s*([^>]*뷔페[^>]*)>',line).group(1).strip()
    return {'kind':kind,'raw_text':line,'name':name,'price_won':price,
            'no_meat_label':True if '(#)' in line else None,
            'price_ambiguous':ambiguous, 'price_status':price_status,
            'price_raw':price_raw}


def restaurant_unit(parent: str, line: str, current: str | None = None) -> str:
    """Explicit named food-court sections; unknown sections never invent tenants."""
    heading = re.match(r'^<\s*([^>]+?)\s*>', line)
    label = normalized(heading.group(1)) if heading else ''
    if parent in ('3식당', '제3식당'):
        return '3식당 든든한끼샐러드코너' if '든든한끼샐러드' in label else (current or '3식당 일반')
    if parent == '75-1동 4층 푸드코트':
        for keyword, unit in (('서가앤쿡','서가앤쿡'), ('토끼정','토끼정'), ('숨쉬는순두부','숨쉬는순두부'), ('이공오','이공오 돈까스와 우동')):
            if keyword in label:
                return f'4층 푸드코드 {unit}'
        return current or parent
    if parent == '두레미담':
        return '두레미담 셀프코너' if '셀프' in label else (current or '두레미담 식당')
    if parent == '301동식당':
        if '천원의아침밥' in label: return '301동식당 천원의아침밥'
        if '교직원전용식당' in label: return '301동 1층 교직원전용식당'
        if '카페 301동' in label: return '카페 301'
        if 'TAKE-OUT' in label.upper(): return '301동식당 TAKE-OUT'
        if label in ('식사','일반'): return '301동식당 일반'
        return current or '301동식당 일반'
    if parent == '예술계식당':
        match = re.search(r'([ABC])\s*코너',label)
        if match: return '예술계식당 ' + match.group(1) + '코너'
        if '직화' in label: return '예술계식당 직화코너'
        return current or parent
    if parent == '220동식당':
        for key, title in [('경성','경성 돈카츠'),('바비든든','바비든든'),('포포420','포포420'),('값찌개','값찌개'),('키친101','키친101')]:
            if key in label: return '220동식당 ' + title
        return current or parent
    return parent


def _restaurant_name(text: str) -> str:
    clean = normalized(PHONE_RE.sub("", normalized(text)))
    # SNUCO marks non-rotating cafeterias with a leading "* ". It is a
    # presentation marker, not part of a restaurant's canonical identity.
    return normalized(re.sub(r"^\*+\s*", "", clean))


def parse_daily_table(html: str, requested_date: date, source: str) -> list[dict]:
    """Read one day from SNUCO or SNUDORM, one output per displayed line."""
    if source not in {"snuco", "snudorm"}:
        raise ValueError("Daily table source must be snuco or snudorm")
    soup = BeautifulSoup(html, "html.parser")
    table = soup.select_one("table.menu-table")
    if table is None:
        raise PageStructureError(f"{source}: table.menu-table missing (possibly blocked or redesigned)")
    date_input = soup.select_one('input[name="date"]')
    if date_input is None or date_input.get("value") != requested_date.isoformat():
        raise PageStructureError(f"{source}: page date not confirmed as {requested_date}")
    body = table.select_one("tbody")
    if body is None:
        raise PageStructureError(f"{source}: no tbody")
    output = []
    rows = body.find_all("tr", recursive=False)
    if not rows:
        raise PageStructureError(f"{source}: no restaurant rows")
    for row in rows:
        cells = row.find_all("td", recursive=False)
        if not cells:
            continue
        label_cell = next((td for td in cells if "title" in td.get("class", [])), cells[0])
        restaurant = _restaurant_name(label_cell.get_text(" ", strip=True))
        if not restaurant:
            raise PageStructureError(f"{source}: empty restaurant name")
        for cell in cells:
            if cell is label_cell:
                continue
            meal = next((MEAL_NAMES[c] for c in cell.get("class", []) if c in MEAL_NAMES), None)
            if meal is None:
                continue
            active_unit = restaurant_unit(restaurant, '', None)
            for idx, line in enumerate(cell_lines(cell)):
                active_unit = restaurant_unit(restaurant, line, active_unit)
                output.append({
                    "source": source, "source_date": requested_date.isoformat(), "restaurant": restaurant,
                    "restaurant_unit": active_unit,
                    "meal_type": meal, "line_order": idx, **classify_line(line),
                })
    return output


def _vet_date(label: str, anchor: date) -> date | None:
    match = VET_DAY_RE.search(label)
    if not match:
        return None
    month, day = map(int, match.group(1, 2))
    wd = WEEKDAY[match.group(3)]
    candidates = []
    for year in (anchor.year - 1, anchor.year, anchor.year + 1):
        try:
            candidate = date(year, month, day)
        except ValueError:
            continue
        if candidate.weekday() == wd:
            candidates.append(candidate)
    if not candidates:
        return None
    closest = min(candidates, key=lambda d: abs((d - anchor).days))
    # A date label alone does not prove the year; reject an implausible year match.
    return closest if abs((closest - anchor).days) <= 35 else None


def parse_vet_week(html: str, *, anchor: date, max_age_days: int = 15) -> list[dict]:
    """Read date-labeled weekly menu rows; reject older-than-window menu tables."""
    soup = BeautifulSoup(html, "html.parser")
    tables = soup.find_all("table")
    candidate_rows = []
    for table in tables:
        rows = table.find_all("tr")
        parsed = []
        for row in rows:
            cells = row.find_all(["td"], recursive=False)
            if len(cells) < 2:
                continue
            day = _vet_date(cells[0].get_text(" ", strip=True), anchor)
            if day is None:
                continue
            parsed.append((day, cells))
        if len(parsed) > len(candidate_rows):
            candidate_rows = parsed
    if not candidate_rows:
        raise PageStructureError("vet: no weekday/date rows in menu table")
    # Avoid treating a month-old unchanged weekly page as current.
    if min(abs((day - anchor).days) for day, _ in candidate_rows) > max_age_days:
        raise PageStructureError("vet: menu week too far from requested range")
    output = []
    for day, cells in candidate_rows:
        for column, meal in ((1, "LUNCH"), (2, "DINNER")):
            if len(cells) <= column:
                continue
            for idx, line in enumerate(cell_lines(cells[column])):
                output.append({"source": "vet", "source_date": day.isoformat(),
                               "restaurant": "수의대식당", "restaurant_unit":"수의대식당",
                               "meal_type": meal, "line_order": idx,
                               **classify_line(line)})
    return output
