"""Synthetic export-contract fixtures; these are NOT captured MySNU responses."""
import copy
import io
import json
import sys
import unittest
from datetime import datetime, timezone
from email.message import Message
from pathlib import Path
from unittest.mock import patch
from urllib.error import URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sync_mysnu as sync

NOW = datetime(2026, 10, 30, 5, 0, tzinfo=timezone.utc)
URL = "https://export.example.org/lost-found?page=1"


def item(source_id="board-123"):
    return {"source_id": source_id, "category": "지갑", "title": "검정 지갑",
            "description": "습득물 설명", "location_name": "이름이 확인된 보관처",
            "latitude": 37.46, "longitude": 126.95,
            "registered_at": "2026-10-29T15:00:00+09:00", "status": "stored", "photo_url": None}


def page(items=None, **changes):
    items = [item()] if items is None else items
    result = {"schema_version": 1, "source": "mysnu-lost-found", "scope": "all-active-items",
              "authenticated": True, "retention_limited": False, "complete": True,
              "snapshot_id": "immutable-export-1", "snapshot_started_at": NOW.isoformat(),
              "page": 1, "total_pages": 1, "total_items": len(items), "items": items, "next": None}
    result.update(changes)
    return result


class Response:
    def __init__(self, body, content_type="application/json", status=200):
        self.body = body.encode() if isinstance(body, str) else body
        self.status = status
        self.headers = Message()
        self.headers["Content-Type"] = content_type
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self, limit): return self.body[:limit]


class SnapshotTests(unittest.TestCase):
    def collect(self, value, **kwargs):
        return sync.collect_snapshot(URL, lambda _: value, {}, NOW, **kwargs)

    def test_full_snapshot_preserves_stable_source_id_and_registration_time(self):
        items, complete = self.collect(page())
        self.assertTrue(complete)
        self.assertEqual("board-123", items[0]["source_id"])
        self.assertEqual("2026-10-29T06:00:00+00:00", items[0]["registered_at"])

    def test_all_pages_with_same_snapshot_are_required(self):
        first = page(total_pages=2, total_items=2, next="?page=2")
        second = page([item("board-124")], page=2, total_pages=2, total_items=2)
        fixtures = {URL: first, "https://export.example.org/lost-found?page=2": second}
        items, complete = sync.collect_snapshot(URL, fixtures.__getitem__, {}, NOW)
        self.assertEqual(["board-123", "board-124"], [x["source_id"] for x in items])
        self.assertTrue(complete)

    def test_partial_filtered_retention_capped_and_unauthenticated_exports_fail(self):
        for change in ({"complete": False}, {"scope": "last-30-days"},
                       {"retention_limited": True}, {"authenticated": False}):
            with self.subTest(change=change), self.assertRaises(sync.SyncError):
                self.collect(page(**change))

    def test_declared_page_count_without_next_link_is_not_completeness(self):
        with self.assertRaisesRegex(sync.SyncError, "missing_next_page"):
            self.collect(page(total_pages=2))

    def test_last_page_empty_is_not_proof_of_total_board_count(self):
        with self.assertRaisesRegex(sync.SyncError, "total_item_count_mismatch"):
            self.collect(page(total_items=20))

    def test_empty_board_requires_two_explicit_signals(self):
        value = page([], empty_confirmed=True)
        with self.assertRaisesRegex(sync.SyncError, "empty_snapshot_requires"):
            self.collect(value)
        self.assertEqual(([], True), self.collect(value, allow_empty=True))
        with self.assertRaises(sync.SyncError):
            self.collect(page([]), allow_empty=True)

    def test_duplicate_ids_fail_even_when_total_count_matches(self):
        with self.assertRaisesRegex(sync.SyncError, "duplicate_source_id"):
            self.collect(page([item(), item()]))

    def test_changed_snapshot_between_pages_fails(self):
        pages = iter([page(total_pages=2, total_items=2, next="?page=2"),
                      page([item("board-124")], page=2, total_pages=2, total_items=2,
                           snapshot_id="new-census")])
        with self.assertRaisesRegex(sync.SyncError, "snapshot_changed"):
            sync.collect_snapshot(URL, lambda _: next(pages), {}, NOW)

    def test_cross_origin_next_never_receives_cookie(self):
        calls = []
        def fetch(url):
            calls.append(url)
            return page(total_pages=2, total_items=2, next="https://other.example.org/page2")
        with self.assertRaisesRegex(sync.SyncError, "cross_origin_pagination"):
            sync.collect_snapshot(URL, fetch, {}, NOW)
        self.assertEqual([URL], calls)

    def test_pagination_cycle_fails(self):
        with self.assertRaisesRegex(sync.SyncError, "pagination_cycle"):
            self.collect(page(total_pages=2, total_items=2, next=URL))

    def test_network_failure_after_first_page_never_returns_partial_items(self):
        calls = 0
        def fetch(_):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise sync.SyncError("network_or_http_failure")
            return page(total_pages=2, total_items=2, next="?page=2")
        with self.assertRaisesRegex(sync.SyncError, "network_or_http_failure"):
            sync.collect_snapshot(URL, fetch, {}, NOW)

    def test_stale_or_timezone_less_snapshot_fails(self):
        for timestamp in ("2026-10-29T05:00:00+00:00", "2026-10-30T05:00:00"):
            with self.subTest(timestamp=timestamp), self.assertRaises(sync.SyncError):
                self.collect(page(snapshot_started_at=timestamp))

    def test_unknown_or_missing_location_does_not_become_campus_center(self):
        for change in ({"location_name": ""}, {"latitude": None}, {"latitude": float("nan")},
                       {"longitude": 0}, {"category": ["지갑"]}, {"source_id": ""}):
            raw = item()
            raw.update(change)
            with self.subTest(change=change), self.assertRaises(sync.SyncError):
                self.collect(page([raw]))

    def test_backend_string_limits_accept_exact_boundaries_after_trimming(self):
        for changes in ({"source_id": "x" * 128, "title": "  가나  ", "description": "",
                         "location_name": "  가나  "},
                        {"source_id": "x", "title": "가" * 100, "description": "나" * 1000,
                         "location_name": "다" * 120}):
            raw = dict(item(), **changes)
            items, _ = self.collect(page([raw]))
            for key in ("source_id", "title", "description", "location_name"):
                self.assertEqual(raw[key].strip(), items[0][key])

    def test_backend_string_limits_reject_outside_boundaries(self):
        for changes in ({"source_id": "x" * 129}, {"title": "  가  "},
                        {"title": "가" * 101}, {"description": "나" * 1001},
                        {"location_name": " 가 "}, {"location_name": "다" * 121}):
            with self.subTest(changes=changes), self.assertRaises(sync.SyncError):
                self.collect(page([dict(item(), **changes)]))

    def test_backend_coordinate_boundaries_are_exact(self):
        for lat, lng in ((33, 124), (39, 132)):
            items, _ = self.collect(page([dict(item(), latitude=lat, longitude=lng)]))
            self.assertEqual((float(lat), float(lng)), (items[0]["latitude"], items[0]["longitude"]))
        for lat, lng in ((32.99999, 126), (39.00001, 126), (37, 123.99999), (37, 132.00001)):
            with self.subTest(latitude=lat, longitude=lng), self.assertRaises(sync.SyncError):
                self.collect(page([dict(item(), latitude=lat, longitude=lng)]))

    def test_police_status_requires_actual_named_verified_institution(self):
        raw = item()
        raw["status"] = "police"
        with self.assertRaisesRegex(sync.SyncError, "unverified_police_destination"):
            self.collect(page([raw]))
        places = {raw["location_name"]: {"latitude": 37.46, "longitude": 126.95}}
        items, _ = sync.collect_snapshot(URL, lambda _: page([raw]), places, NOW)
        self.assertEqual(raw["location_name"], items[0]["location_name"])
        raw["latitude"] = 37.5
        with self.assertRaisesRegex(sync.SyncError, "police_coordinates_mismatch"):
            sync.collect_snapshot(URL, lambda _: page([raw]), places, NOW)

    def test_verified_police_mapping_needs_official_source_and_recent_review(self):
        base = {"name": "검증용 기관명", "latitude": 37.46, "longitude": 126.95,
                "source_url": "https://www.police.go.kr/verified-fixture", "checked_on": "2026-10-30"}
        self.assertIn(base["name"], sync.verified_locations([base], NOW))
        for changes in ({"source_url": "https://not-police.example.org/x"},
                        {"checked_on": "2024-10-30"}, {"checked_on": "2026-11-01"}):
            with self.subTest(changes=changes), self.assertRaises(sync.SyncError):
                sync.verified_locations([dict(base, **changes)], NOW)


class TransportTests(unittest.TestCase):
    def request(self, response):
        with patch.object(sync, "build_opener") as mocked:
            mocked.return_value.open.return_value = response
            return sync.request_json(URL)

    def test_html_login_page_is_not_an_empty_export(self):
        with self.assertRaisesRegex(sync.SyncError, "non_json_response"):
            self.request(Response('<html><form action="login"><input type="password"></form></html>', "text/html"))

    def test_json_login_and_malformed_payload_cannot_be_parsed_as_records(self):
        for value in ({"login": True}, [], {"items": []}):
            with self.subTest(value=value), self.assertRaises(sync.SyncError):
                sync.collect_snapshot(URL, lambda _: value, {}, NOW)

    def test_redirects_are_rejected_instead_of_following_sso(self):
        with self.assertRaisesRegex(sync.SyncError, "http_redirect_rejected"):
            sync.NoRedirect().redirect_request(None, None, 302, None, {}, "https://sso.snu.ac.kr/login")

    def test_duplicate_json_keys_and_nonstandard_constants_fail(self):
        for body in ('{"items":[],"items":[]}', '{"latitude":NaN}', '<not json>'):
            with self.subTest(body=body), self.assertRaises(sync.SyncError):
                self.request(Response(body))

    def test_oversize_response_fails(self):
        with self.assertRaisesRegex(sync.SyncError, "response_too_large"):
            self.request(Response(b" " * (sync.MAX_BYTES + 1)))

    def test_network_errors_have_no_source_url_or_secret_in_diagnostic(self):
        with patch.object(sync, "build_opener") as mocked:
            mocked.return_value.open.side_effect = URLError("private-secret-cookie")
            with self.assertRaises(sync.SyncError) as caught:
                sync.request_json(URL)
            self.assertNotIn("private-secret", str(caught.exception))

    def test_invalid_destination_urls_fail(self):
        for url in ("http://example.org", "https://user:secret@example.org", "https://example.org:8443/x",
                    "https://example.org/\r\nheader", "file:///x"):
            with self.subTest(url=url), self.assertRaises(sync.SyncError):
                sync.https_url(url)

    def test_unconfigured_source_or_cookie_to_external_exporter_cannot_sync(self):
        with patch.object(sync, "request_json") as request:
            for config in ({}, {"MYSNU_SOURCE_MODE": "export", "MYSNU_FEED_URL": URL, "MYSNU_COOKIE": "session=private"}):
                with self.subTest(config=config), self.assertRaises(sync.SyncError):
                    sync.run(config)
            request.assert_not_called()

    def test_failed_source_never_calls_service_rpc(self):
        with patch.object(sync, "request_json", return_value={"login": True}) as request:
            with self.assertRaises(sync.SyncError):
                sync.run({"MYSNU_SOURCE_MODE": "export", "MYSNU_FEED_URL": URL, "SUPABASE_URL": "https://fixture.supabase.co",
                          "SUPABASE_SERVICE_ROLE_KEY": "not-a-real-key"})
            self.assertEqual(1, request.call_count)

    def test_dry_run_never_needs_service_credential(self):
        value = page(snapshot_started_at=datetime.now(timezone.utc).isoformat())
        with patch.object(sync, "request_json", return_value=value) as request:
            self.assertEqual({"items": 1, "complete": True, "dry_run": True},
                             sync.run({"MYSNU_SOURCE_MODE": "export", "MYSNU_FEED_URL": URL}, dry_run=True))
            self.assertEqual(1, request.call_count)

    def test_full_census_uses_service_only_rpc_and_a_fresh_uuid(self):
        value = page(snapshot_started_at=datetime.now(timezone.utc).isoformat())
        config = {"MYSNU_SOURCE_MODE": "export", "MYSNU_FEED_URL": URL, "SUPABASE_URL": "https://fixture.supabase.co",
                  "SUPABASE_SERVICE_ROLE_KEY": "server-test-credential"}
        with patch.object(sync, "request_json", side_effect=[value, {"ok": True}]) as request:
            result = sync.run(config)
            upload = request.call_args_list[1]
            self.assertEqual("https://fixture.supabase.co/rest/v1/rpc/lf_sync_mysnu", upload.args[0])
            self.assertTrue(upload.kwargs["data"]["p_complete"])
            self.assertEqual("board-123", upload.kwargs["data"]["p_items"][0]["source_id"])
            self.assertEqual(4, sync.uuid.UUID(upload.kwargs["data"]["p_run_id"]).version)
            self.assertFalse(result["dry_run"])


if __name__ == "__main__":
    unittest.main()
