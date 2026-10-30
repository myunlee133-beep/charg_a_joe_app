"""MySNU HTML adapter, based on the authenticated board observed 2026-10-30.

No password handling or browser-session extraction. Locations are supplied by
the operator, not guessed from a campus/police centroid. Unknown markup fails.
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from urllib.parse import parse_qs, urljoin, urlsplit
from urllib.request import Request, build_opener

from sync_mysnu import (MAX_BYTES, MAX_PAGES, NoRedirect, SyncError, coordinate,
                       normalize_item, require)

BOARD = "https://my.snu.ac.kr/p/ST050102/?b=1&ls=20&ln=1&px=7&dm=m&inB=&inPx="
KST = timezone(timedelta(hours=9))


class Node:
    def __init__(self, tag="", attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        return " ".join(x.text() if isinstance(x, Node) else x for x in self.children)

    def find(self, *, tag=None, cls=None, attr=None):
        result = []
        for child in self.children:
            if not isinstance(child, Node):
                continue
            if ((tag is None or child.tag == tag)
                    and (cls is None or cls in child.attrs.get("class", "").split())
                    and (attr is None or child.attrs.get(attr[0]) == attr[1])):
                result.append(child)
            result.extend(child.find(tag=tag, cls=cls, attr=attr))
        return result


class Document(HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root, self.stack = Node(), []
        self.stack.append(self.root)
        self.feed(html)
        require(not self.root.find(tag="input", attr=("type", "password")), "portal_login_page")
        require("로그아웃" in self.root.text(), "portal_authentication_not_confirmed")

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        if self.stack[-1].tag not in ("script", "style"):
            self.stack[-1].children.append(data)


def compact(value):
    return re.sub(r"\s+", "", value)


def one(nodes, code):
    require(len(nodes) == 1, code)
    return nodes[0]


def board_url(url, *, detail=False, page=None):
    parsed = urlsplit(url)
    require(parsed.scheme == "https" and parsed.netloc == "my.snu.ac.kr"
            and parsed.path == "/p/ST050102/" and not parsed.fragment,
            "unexpected_portal_destination")
    q = parse_qs(parsed.query, keep_blank_values=True)
    require(all(len(v) == 1 for v in q.values()), "duplicate_portal_parameter")
    require(q.get("b") == ["1"] and q.get("px") == ["7"], "wrong_portal_board")
    require(set(q) <= {"b", "px", "ls", "ln", "dm", "p", "inB", "inPx"}
            and not q.get("inB", [""])[0] and not q.get("inPx", [""])[0],
            "filtered_portal_board")
    require(q.get("dm", ["m"]) == (["r"] if detail else ["m"]), "wrong_portal_mode")
    require(detail == ("p" in q), "wrong_portal_mode")
    if detail:
        require(q["p"][0].isdigit(), "invalid_portal_post_id")
    if page is not None:
        require(q.get("ln", ["1"]) == [str(page)], "wrong_portal_page")
    return q


def request_html(url, cookie):
    board_url(url, detail="p=" in urlsplit(url).query)
    require(bool(cookie) and "\r" not in cookie and "\n" not in cookie,
            "portal_session_required")
    try:
        with build_opener(NoRedirect()).open(Request(url, headers={
                "Accept": "text/html", "Cookie": cookie,
                "User-Agent": "Chajajwo-LostFound-Sync/1"}), timeout=30) as response:
            require(response.status == 200 and response.headers.get_content_type() == "text/html",
                    "unexpected_portal_response")
            raw = response.read(MAX_BYTES + 1)
            require(len(raw) <= MAX_BYTES, "response_too_large")
            return raw.decode(response.headers.get_content_charset() or "utf-8")
    except SyncError:
        raise
    except Exception as error:
        raise SyncError("portal_network_or_http_failure") from error


def census(fetch):
    """Traverse links exposed by the board, verifying its count and every row."""
    url, page, expected_total, page_size = BOARD, 1, None, None
    rows, ids = [], set()
    while url:
        require(page <= MAX_PAGES, "portal_page_limit")
        q = board_url(url, page=page)
        if page_size is None:
            size = q.get("ls", [""])[0]
            require(size.isdigit() and int(size) in (10, 20, 30, 40, 50, 60),
                    "invalid_portal_page_size")
            page_size = int(size)
        doc = Document(fetch(url)).root
        count = one(doc.find(cls="bc-s-sum"), "missing_portal_total").text().strip()
        require(re.fullmatch(r"[\d,]+건", count) is not None, "invalid_portal_total")
        total = int(count[:-1].replace(",", ""))
        require(0 < total <= 100000, "portal_empty_or_invalid_total")
        if expected_total is None:
            expected_total = total
        require(total == expected_total, "portal_changed_during_census")
        current = doc.find(tag="ul", attr=("data-name", "post_list"))
        require(bool(current), "missing_portal_rows")
        next_links = {}
        for link in doc.find(tag="a"):
            target = urljoin(url, link.attrs.get("href", ""))
            parsed = urlsplit(target)
            if parsed.path != "/p/ST050102/" or "ln=" not in parsed.query:
                continue
            link_q = board_url(target)
            n = link_q.get("ln", [""])[0]
            require(n.isdigit(), "invalid_portal_page_link")
            size = link_q.get("ls", [""])[0]
            require(size.isdigit() and int(size) in (10, 20, 30, 40, 50, 60),
                    "invalid_portal_page_size")
            if page_size is None:
                page_size = int(size)
            require(int(size) == page_size, "portal_page_size_changed")
            next_links[int(n)] = target
        require(page_size is not None, "missing_portal_pagination")
        require(q.get("ls", [str(page_size)]) == [str(page_size)], "portal_page_size_changed")
        remaining = total - len(rows)
        require(len(current) == min(page_size, remaining), "portal_row_count_mismatch")
        for row in current:
            pid = one(row.find(cls="bc-s-post_seq"), "missing_portal_post_id").text().strip()
            require(pid.isdigit() and pid not in ids, "duplicate_or_invalid_portal_post_id")
            require(one(row.find(cls="bc-s-prefix"), "missing_portal_category").text().strip()
                    == "분실물", "wrong_portal_category")
            detail_url = urljoin(url, row.attrs.get("data-url", ""))
            require(board_url(detail_url, detail=True).get("p") == [pid], "portal_post_id_mismatch")
            title = one(row.find(cls="bc-s-title"), "missing_portal_title").text().strip()
            date = one(row.find(cls="bc-s-cre_dt"), "missing_portal_date").text().strip()
            require(re.fullmatch(r"\d{4}\.\d{2}\.\d{2}", date) is not None, "invalid_portal_date")
            rows.append({"id": pid, "url": detail_url, "title": title, "date": date})
            ids.add(pid)
        url = next_links.get(page + 1) if len(rows) < total else None
        require(url is not None or len(rows) == total, "missing_portal_next_page")
        page += 1
    return rows


def detail(row, html):
    doc = Document(html).root
    title = one(doc.find(cls="tit"), "missing_portal_detail_title").text().strip()
    require(title == row["title"], "portal_detail_title_changed")
    body = one(doc.find(cls="text_area"), "missing_portal_detail_body").text().strip()
    dates = [dl for dl in doc.find(tag="dl")
             if dl.find(tag="dt") and dl.find(tag="dt")[0].text().strip() == "작성일"]
    registered = one(one(dates, "missing_portal_registration").find(tag="dd"),
                     "missing_portal_registration").text().strip()
    try:
        stamp = datetime.strptime(registered, "%Y.%m.%d %H:%M:%S").replace(tzinfo=KST)
    except ValueError as error:
        raise SyncError("invalid_portal_registration") from error
    require(stamp.strftime("%Y.%m.%d") == row["date"], "portal_registration_changed")
    return body, stamp


def category(title):
    for result, words in (("지갑", ("지갑",)), ("학생증", ("학생증", "신분증")),
                          ("전자기기", ("이어폰", "에어팟", "워치", "태블릿", "충전", "배터리", "USB", "스마트폰", "휴대폰", "선풍기")),
                          ("우산", ("우산", "양산")), ("의류", ("의류", "옷", "후드", "모자", "점퍼", "짚업")),
                          ("가방", ("가방", "파우치")), ("열쇠", ("열쇠", "키링"))):
        if any(word.lower() in title.lower() for word in words):
            return result
    return "기타"


def storage_locations(raw):
    try:
        entries = json.loads(raw)
    except (TypeError, ValueError) as error:
        raise SyncError("invalid_storage_locations") from error
    require(isinstance(entries, list) and bool(entries), "storage_locations_required")
    result = []
    for entry in entries:
        require(isinstance(entry, dict) and isinstance(entry.get("name"), str)
                and 2 <= len(entry["name"]) <= 120, "invalid_storage_location")
        aliases = entry.get("aliases")
        require(isinstance(aliases, list) and aliases
                and all(isinstance(a, str) and len(compact(a)) >= 4 for a in aliases),
                "invalid_storage_aliases")
        result.append({"name": entry["name"], "aliases": aliases,
                       "latitude": coordinate(entry.get("latitude"), 33, 39),
                       "longitude": coordinate(entry.get("longitude"), 124, 132)})
    return result


def collect_portal(fetch, places, storage, now):
    before = census(fetch)
    posts = [(row, *detail(row, fetch(row["url"]))) for row in before]
    transfers, candidates = {}, []
    for row, body, stamp in posts:
        title = compact(row["title"]).strip("*")
        # Older records (observed on the final page) replace the item title
        # with a completed transfer/disposal label, without an inventory number.
        if title == "폐기完":
            continue
        legacy_police = re.fullmatch(r"(.+?경찰서)이관작업完", title)
        if legacy_police:
            require(legacy_police[1] in places, "unverified_police_destination")
            candidates.append((row, body, stamp, None, legacy_police[1]))
            continue
        # Monthly notices are metadata, never one more lost item on the map.
        transfer = re.fullmatch(r"(\d{4})년(\d{1,2})월분미수령물품(.+?경찰서)이관", title)
        if transfer:
            key = (int(transfer[1]), int(transfer[2]))
            require(1 <= key[1] <= 12 and transfer[3] in places, "unverified_police_destination")
            require(key not in transfers or transfers[key] == transfer[3], "conflicting_police_transfers")
            transfers[key] = transfer[3]
            continue
        if "분실물센터위치및운영시간안내" in title:
            continue
        # An unfamiliar notice must be reviewed; silently dropping it could mark
        # existing records received during a complete sync.
        number = re.search(r"분실물번호[:：](\d{2,4})-(\d{1,2})-\d+", compact(body))
        require(number is not None, "unrecognized_portal_item_or_notice")
        year = int(number[1]) + (2000 if len(number[1]) == 2 else 0)
        month = int(number[2])
        require(1 <= month <= 12, "invalid_portal_item_number")
        candidates.append((row, body, stamp, (year, month), None))
    items = []
    for row, body, stamp, month, legacy_police in candidates:
        police = legacy_police or transfers.get(month)
        explicit = re.search(r"(.+?경찰서)이관(?:완료)?$", compact(row["title"]).strip("*"))
        if explicit:
            matches = [name for name in places if explicit[1].endswith(name)]
            require(len(matches) == 1, "unverified_police_destination")
            police = matches[0]
        if police:
            location = {"name": police, **places[police]}
        else:
            matches = [entry for entry in storage
                       if any(compact(alias) in compact(body) for alias in entry["aliases"])]
            location = one(matches, "unknown_or_ambiguous_portal_storage")
        # Publish just the item descriptor, not boilerplate identity-proof or
        # contact information. Original authenticated photo URLs stay private.
        description = re.sub(r"\s+", " ", body.split("※", 1)[0]).strip()[:1000]
        items.append(normalize_item({"source_id": row["id"], "title": row["title"],
                     "category": category(row["title"]), "description": description,
                     "registered_at": stamp.isoformat(), "status": "police" if police else "stored",
                     "location_name": location["name"], "latitude": location["latitude"],
                     "longitude": location["longitude"], "photo_url": None}, places, now))
    after = census(fetch)
    # Stable full-board IDs and metadata at both ends, rather than a recent-N
    # cap or a lone empty page. A changed portal triggers a whole-job retry.
    require(before == after, "portal_changed_during_collection")
    require(bool(items), "portal_no_recognized_items")
    return items, True
