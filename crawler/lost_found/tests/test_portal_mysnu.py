"""Reduced observed markup; synthetic item data, no session or personal data."""
import sys
import unittest
from datetime import datetime, timezone
from html import escape
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import portal_mysnu as portal
import sync_mysnu as sync

NOW = datetime(2026, 10, 30, tzinfo=timezone.utc)
STORAGE = [{"name": "아시아연구소 1층 분실물센터", "aliases": ["아시아연구소 1층 분실물센터"],
            "latitude": 37.46328, "longitude": 126.95015}]
# Test-only police location; production requires independently verified settings.
POLICE = {"관악경찰서": {"latitude": 37.47, "longitude": 126.95}}


def post(pid="26689", title="10-57 파우치(태블릿 포함)", body=None, date="2026.10.21"):
    return {"id": pid, "title": title, "date": date,
            "body": body if body is not None else (
                "분실물 번호 : 26-10-57 1. 입 고 일 : 26.10.20. 2. 물 품 : 파우치(태블릿 포함)"
                " ※ 물품 보관기간 : 1개월 - 1개월 후 관악경찰서 이관 "
                "아시아연구소 1층 분실물센터")}


def list_html(posts, total=None, next_page=None):
    total = len(posts) if total is None else total
    rows = []
    for p in posts:
        url = f'/p/ST050102/?b=1&ls=20&ln=1&px=7&dm=r&p={p["id"]}'
        rows.append(f'<ul data-name="post_list" data-url="{escape(url)}">'
                    f'<li class="bc-s-post_seq">{p["id"]}</li>'
                    '<li class="bc-s-prefix"><span>분실물</span></li>'
                    f'<li class="bc-s-title"><div class="postT"><span>{escape(p["title"])}</span></div></li>'
                    f'<li class="bc-s-cre_dt">{p["date"]}</li></ul>')
    next_link = (f'<a href="/p/ST050102/?b=1&ls=20&ln={next_page}&px=7&dm=m&inB=&inPx=">'
                 f'{next_page}</a>') if next_page else ""
    return f'<a>로그아웃</a><span class="bc-s-sum">{total:,}건</span>' + "".join(rows) + next_link


def detail_html(p):
    return ('<a>로그아웃</a><ul class="row col-12 tit"><li><h3>' + escape(p["title"])
            + '</h3></li></ul><dl><dt>분류</dt><dd>분실물</dd></dl>'
            + f'<dl><dt>작성일</dt><dd>{p["date"]} 14:08:40</dd></dl>'
            + '<div class="text_area"><p>' + escape(p["body"])
            + '</p><img src="https://my.snu.ac.kr/private-photo.jpg"></div>')


def fetcher(posts, *, mutate_after=False):
    reads = 0
    def fetch(url):
        nonlocal reads
        if "dm=r" in url:
            pid = portal.board_url(url, detail=True)["p"][0]
            return detail_html(next(p for p in posts if p["id"] == pid))
        reads += 1
        html = list_html(posts)
        return html.replace("26689", "99999") if mutate_after and reads > 1 else html
    return fetch


class PortalTests(unittest.TestCase):
    def test_bundled_locations_have_verified_station_and_current_storage(self):
        import json
        config = json.loads(Path(portal.__file__).with_name("locations.json").read_text(encoding="utf-8"))
        places = sync.verified_locations(config["police"], NOW)
        self.assertIn("관악경찰서", places)
        self.assertTrue(37.474 < places["관악경찰서"]["latitude"] < 37.475)
        self.assertTrue(126.950 < places["관악경찰서"]["longitude"] < 126.952)
        storage = portal.storage_locations(json.dumps(config["storage"]))
        self.assertIn("101동", storage[0]["name"])

    def test_missing_bundled_config_aborts_without_network_or_database(self):
        with patch.object(Path, "read_text", side_effect=OSError("synthetic file failure")), \
             patch.object(portal, "request_html") as source, patch.object(sync, "request_json") as rpc:
            with self.assertRaisesRegex(sync.SyncError, "invalid_portal_location_configuration"):
                sync.run({"MYSNU_SOURCE_MODE": "portal"})
            source.assert_not_called()
            rpc.assert_not_called()

    def test_observed_list_detail_shape_and_future_boilerplate(self):
        items, complete = portal.collect_portal(fetcher([post()]), POLICE, STORAGE, NOW)
        self.assertTrue(complete)
        self.assertEqual("26689", items[0]["source_id"])
        self.assertEqual("stored", items[0]["status"])
        self.assertEqual("아시아연구소 1층 분실물센터", items[0]["location_name"])
        self.assertEqual("전자기기", items[0]["category"])
        self.assertEqual("2026-10-21T05:08:40+00:00", items[0]["registered_at"])
        self.assertIn("입 고 일", items[0]["description"])
        self.assertNotIn("보관기간", items[0]["description"])
        self.assertIsNone(items[0]["photo_url"])

    def test_inspected_details_use_same_normalizer_without_claiming_completeness(self):
        row = post()
        body, stamp = portal.detail(row, detail_html(row))
        inspected = portal.normalize_posts([(row, body, stamp)], POLICE, STORAGE, NOW)
        full, complete = portal.collect_portal(fetcher([row]), POLICE, STORAGE, NOW)
        self.assertEqual(inspected, full)
        self.assertIsInstance(inspected, list)
        self.assertTrue(complete)

    def test_monthly_notice_transfers_only_matching_year_and_month(self):
        aug = post("26369", "8-40 스마트워치", "분실물 번호 : 26-8-40 아시아연구소 1층 분실물센터", "2026.08.31")
        notice = post("26370", "***** 2026년 8월분 미수령 물품 관악경찰서 이관 *****",
                      "2026년 8월분 미수령 물품 관악경찰서 이관", "2026.08.31")
        items, _ = portal.collect_portal(fetcher([post(), notice, aug]), POLICE, STORAGE, NOW)
        self.assertEqual(2, len(items))
        self.assertEqual(["stored", "police"], [i["status"] for i in items])
        self.assertEqual("관악경찰서", items[1]["location_name"])
        self.assertEqual(POLICE["관악경찰서"]["latitude"], items[1]["latitude"])

    def test_location_notice_is_not_an_item(self):
        notice = post("26627", "***** 분실물센터 위치 및 운영시간 안내 *****", "아시아연구소 1층")
        items, _ = portal.collect_portal(fetcher([post(), notice]), {}, STORAGE, NOW)
        self.assertEqual(1, len(items))

    def test_old_transfer_and_disposal_labels_from_final_page(self):
        old = post("6945", "관악경찰서 이관작업 完", "1. 습득날짜 : 21.08.18 2. 특징 : 검은색 케이스", "2021.08.24")
        disposed = post("6938", "폐기 完", "1. 습득날짜 : 21.08.11 2. 특징 : 카드", "2021.08.24")
        items, complete = portal.collect_portal(fetcher([old, disposed]), POLICE, STORAGE, NOW)
        self.assertTrue(complete)
        self.assertEqual(["6945"], [i["source_id"] for i in items])
        self.assertEqual("police", items[0]["status"])
        self.assertEqual("관악경찰서", items[0]["location_name"])

    def test_unverified_police_unknown_item_and_missing_location_abort(self):
        cases = [post(body="분실물 번호 : 26-10-57 보관장소 미상"),
                 post(title="알 수 없는 공지", body="새로운 안내"),
                 post(title="2026년 8월분 미수령 물품 관악경찰서 이관", body="이관")]
        for p in cases:
            with self.subTest(p=p["title"]), self.assertRaises(sync.SyncError):
                portal.collect_portal(fetcher([p]), {}, STORAGE, NOW)

    def test_changed_census_aborts_instead_of_marking_missing_items_received(self):
        with self.assertRaisesRegex(sync.SyncError, "portal_changed_during_collection"):
            portal.collect_portal(fetcher([post()], mutate_after=True), {}, STORAGE, NOW)

    def test_all_pages_are_counted_and_next_link_must_exist(self):
        posts = [post(str(1000 + i)) for i in range(21)]
        first = list_html(posts[:20], total=21, next_page=2)
        second = list_html(posts[20:], total=21)
        rows = portal.census(lambda url: second if "ln=2" in url else first)
        self.assertEqual(21, len(rows))
        with self.assertRaisesRegex(sync.SyncError, "missing_portal_next_page"):
            portal.census(lambda _: list_html(posts[:20], total=21))

    def test_login_wrong_category_count_mismatch_and_duplicate_ids_abort(self):
        bad = ['<input type="password">', list_html([post()]).replace("분실물</span>", "전체</span>"),
               list_html([post()], total=2), list_html([post(), post()])]
        for html in bad:
            with self.subTest(html=html[:40]), self.assertRaises(sync.SyncError):
                portal.census(lambda _: html)

    def test_cross_origin_and_filtered_links_cannot_receive_cookie(self):
        for url in (portal.BOARD.replace("my.snu.ac.kr", "evil.example"),
                    portal.BOARD + "&q=test", portal.BOARD + "&px=8"):
            with self.assertRaises(sync.SyncError):
                portal.board_url(url)

    def test_new_mode_never_writes_database_after_source_failure(self):
        settings = {"MYSNU_SOURCE_MODE": "portal", "MYSNU_COOKIE": "synthetic-test-cookie",
                    "MYSNU_STORAGE_LOCATIONS": '[{"name":"분실물센터","aliases":["아시아연구소"],"latitude":37.46,"longitude":126.95}]'}
        with patch.object(portal, "request_html", return_value='<input type="password">'), \
             patch.object(sync, "request_json") as rpc:
            with self.assertRaises(sync.SyncError):
                sync.run(settings)
            rpc.assert_not_called()

    def test_portal_dry_run_uses_common_database_contract_without_writing(self):
        import json
        settings = {"MYSNU_SOURCE_MODE": "portal", "MYSNU_COOKIE": "synthetic-test-cookie",
                    "MYSNU_STORAGE_LOCATIONS": json.dumps(STORAGE)}
        with patch.object(portal, "request_html", side_effect=lambda url, cookie: fetcher([post()])(url)), \
             patch.object(sync, "request_json") as rpc:
            result = sync.run(settings, dry_run=True)
            self.assertEqual({"items": 1, "complete": True, "dry_run": True}, result)
            rpc.assert_not_called()

    def test_portal_collection_is_submitted_through_real_sync_contract(self):
        import json
        settings = {"MYSNU_COOKIE": "synthetic-test-cookie", "MYSNU_STORAGE_LOCATIONS": json.dumps(STORAGE),
                    "SUPABASE_URL": "https://fixture.supabase.co", "SUPABASE_SECRET_KEY": "sb_secret_synthetic"}
        source = fetcher([post()])
        with patch.object(portal, "request_html", side_effect=lambda url, cookie: source(url)), \
             patch.object(portal.time, "sleep"), \
             patch.object(sync, "request_json", return_value={"ok": True, "seen": 1, "inserted": 1, "updated": 0, "removed": 0}) as rpc:
            result = sync.run(settings)
        rpc.assert_called_once()
        data = rpc.call_args.kwargs["data"]
        self.assertTrue(data["p_complete"])
        self.assertEqual("26689", data["p_items"][0]["source_id"])
        self.assertEqual("stored", data["p_items"][0]["status"])
        self.assertIsNone(data["p_items"][0]["photo_url"])
        self.assertEqual(1, result["sync"]["inserted"])

    def test_request_spacing_applies_to_sequential_reads(self):
        with patch.object(portal.time, "monotonic", side_effect=[0, 0.1, 0.25]), \
             patch.object(portal.time, "sleep") as sleep, patch.object(portal, "request_html", return_value="html") as request:
            reader = portal.portal_reader("synthetic-cookie", 0.25)
            reader(portal.BOARD)
            reader(portal.BOARD)
        self.assertAlmostEqual(0.15, sleep.call_args.args[0])
        self.assertEqual(2, request.call_count)

    def test_invalid_request_interval_cannot_collect_or_sync(self):
        for value in ("0", "nan", "inf", "100", "not-a-number"):
            with self.subTest(value=value), patch.object(portal, "request_html") as source, \
                 patch.object(sync, "request_json") as rpc, self.assertRaisesRegex(sync.SyncError, "invalid_portal_request_interval"):
                sync.run({"MYSNU_COOKIE": "synthetic-cookie", "MYSNU_REQUEST_INTERVAL_SECONDS": value}, dry_run=True)
            source.assert_not_called()
            rpc.assert_not_called()


if __name__ == "__main__":
    unittest.main()
