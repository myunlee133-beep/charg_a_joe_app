"""Fail-closed MySNU lost-item synchronization via verified export or portal HTML.

No source URL, credentials, records, or responses are logged. See README.md for
operator authentication, location verification, and live-validation requirements.
"""
from __future__ import annotations

import argparse
import getpass
import json
import math
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

MAX_BYTES = 8 * 1024 * 1024
MAX_PAGES = 2000
CATEGORIES = {"지갑", "전자기기", "학생증", "우산", "의류", "가방", "열쇠", "기타"}


class SyncError(Exception):
    """Safe, fixed diagnostic code; never include source/server text or secrets."""


def require(condition: bool, code: str) -> None:
    if not condition:
        raise SyncError(code)


def https_url(value: object) -> str:
    require(isinstance(value, str) and bool(value), "invalid_https_url")
    require(not any(ch.isspace() or ord(ch) < 32 for ch in value), "invalid_https_url")
    try:
        parsed = urlsplit(value)
        require(parsed.scheme == "https" and bool(parsed.hostname) and parsed.username is None
                and parsed.password is None and not parsed.fragment and parsed.port in (None, 443),
                "invalid_https_url")
    except ValueError as error:
        raise SyncError("invalid_https_url") from error
    return value


def origin(url: str) -> tuple[str, str, int]:
    parsed = urlsplit(https_url(url))
    return parsed.scheme, parsed.hostname.lower(), parsed.port or 443


def instant(value: object, code: str = "invalid_timestamp") -> datetime:
    require(isinstance(value, str), code)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise SyncError(code) from error
    require(parsed.tzinfo is not None and parsed.utcoffset() is not None, code)
    return parsed.astimezone(timezone.utc)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Expired authentication must never turn a login page into an empty board.
        raise SyncError("http_redirect_rejected")


def request_json(url: str, *, headers: dict[str, str] | None = None,
                 data: dict | None = None) -> object:
    https_url(url)
    safe_headers = {"Accept": "application/json", "User-Agent": "Chajajwo-LostFound-Sync/1"}
    safe_headers.update(headers or {})
    body = None
    if data is not None:
        body = json.dumps(data, ensure_ascii=False, allow_nan=False).encode("utf-8")
        safe_headers["Content-Type"] = "application/json; charset=utf-8"
    request = Request(url, data=body, headers=safe_headers, method="POST" if data is not None else "GET")
    try:
        with build_opener(NoRedirect()).open(request, timeout=30) as response:
            require(response.status == 200, "http_status_rejected")
            require(response.headers.get_content_type() == "application/json", "non_json_response")
            raw = response.read(MAX_BYTES + 1)
            require(len(raw) <= MAX_BYTES, "response_too_large")
    except (HTTPError, URLError, OSError, ValueError) as error:
        raise SyncError("network_or_http_failure") from error
    try:
        # Reject duplicate keys and non-standard NaN/Infinity rather than relying on
        # parser overwrite behavior for source IDs or completeness declarations.
        def unique_pairs(pairs):
            result = {}
            for key, value in pairs:
                require(key not in result, "duplicate_json_key")
                result[key] = value
            return result
        def invalid_constant(_):
            raise SyncError("invalid_json_constant")
        return json.loads(raw.decode("utf-8"), object_pairs_hook=unique_pairs,
                          parse_constant=invalid_constant)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise SyncError("invalid_json_response") from error


def text(value: object, minimum: int, maximum: int, code: str) -> str:
    require(isinstance(value, str) and minimum <= len(value.strip()) <= maximum, code)
    require(not any(ord(ch) < 32 and ch not in "\n\t" for ch in value), code)
    return value.strip()


def coordinate(value: object, low: float, high: float) -> float:
    require(type(value) in (int, float) and math.isfinite(value) and low <= value <= high,
            "invalid_coordinates")
    return float(value)


def verified_locations(raw: object, now: datetime) -> dict[str, dict]:
    """Operator-reviewed, named police destinations; no default police pin exists."""
    require(isinstance(raw, list), "invalid_verified_locations")
    result = {}
    for entry in raw:
        require(isinstance(entry, dict), "invalid_verified_locations")
        name = text(entry.get("name"), 2, 120, "invalid_verified_location_name")
        require(name not in result, "duplicate_verified_location")
        url = https_url(entry.get("source_url"))
        host = urlsplit(url).hostname.lower()
        require(host == "police.go.kr" or host.endswith(".police.go.kr")
                or host == "smpa.go.kr" or host.endswith(".smpa.go.kr")
                or host == "lost112.go.kr" or host.endswith(".lost112.go.kr"),
                "police_verification_source_required")
        try:
            checked = datetime.fromisoformat(entry.get("checked_on", "")).date()
        except (ValueError, TypeError) as error:
            raise SyncError("invalid_location_verification_date") from error
        require(now.date() - timedelta(days=365) <= checked <= now.date(),
                "outdated_location_verification")
        result[name] = {"latitude": coordinate(entry.get("latitude"), 33, 39),
                        "longitude": coordinate(entry.get("longitude"), 124, 132)}
    return result


def normalize_item(raw: object, places: dict[str, dict], now: datetime) -> dict:
    require(isinstance(raw, dict), "invalid_item")
    source_id = text(raw.get("source_id"), 1, 128, "invalid_source_id")
    require(not any(ch.isspace() for ch in source_id), "invalid_source_id")
    category = raw.get("category")
    require(isinstance(category, str) and category in CATEGORIES, "invalid_category")
    status = raw.get("status")
    require(status in ("stored", "police"), "invalid_source_status")
    location = text(raw.get("location_name"), 2, 120, "missing_actual_location")
    latitude = coordinate(raw.get("latitude"), 33, 39)
    longitude = coordinate(raw.get("longitude"), 124, 132)
    if status == "police":
        require(location in places, "unverified_police_destination")
        # The institution, not a generic campus/police fallback, owns this pin.
        verified = places[location]
        require(abs(latitude - verified["latitude"]) <= 0.0001
                and abs(longitude - verified["longitude"]) <= 0.0001,
                "police_coordinates_mismatch")
        latitude, longitude = verified["latitude"], verified["longitude"]
    registered = instant(raw.get("registered_at"))
    require(registered <= now + timedelta(minutes=5), "future_registration_time")
    photo = raw.get("photo_url")
    if photo is not None:
        photo = https_url(photo)
    return {"source_id": source_id, "category": category,
            "title": text(raw.get("title"), 2, 100, "invalid_title"),
            "description": text(raw.get("description"), 0, 1000, "invalid_description"),
            "location_name": location, "latitude": latitude, "longitude": longitude,
            "registered_at": registered.isoformat(), "status": status, "photo_url": photo}


def collect_snapshot(url: str, fetch, places: dict[str, dict], now: datetime,
                     *, allow_empty: bool = False) -> tuple[list[dict], bool]:
    """Fetch every page from one immutable, full-board snapshot before any write.

    Exporter assertions must derive from actual authenticated pagination and a
    stable full-board ID census, never a recent-items cap or merely an empty page.
    Missing/mismatched evidence fails the entire job and suppresses the RPC.
    """
    https_url(url)
    first_origin = origin(url)
    seen_urls, items, ids = set(), [], set()
    expected, page_number, current = None, 1, url
    while current is not None:
        require(current not in seen_urls, "pagination_cycle")
        require(origin(current) == first_origin, "cross_origin_pagination")
        seen_urls.add(current)
        page = fetch(current)
        require(isinstance(page, dict), "invalid_export_envelope")
        require(type(page.get("schema_version")) is int and page["schema_version"] == 1 and page.get("source") == "mysnu-lost-found"
                and page.get("scope") == "all-active-items", "unexpected_source_contract")
        require(page.get("authenticated") is True, "unauthenticated_source")
        require(page.get("retention_limited") is False and page.get("complete") is True,
                "incomplete_snapshot")
        require(type(page.get("page")) is int and page["page"] == page_number,
                "unexpected_page")
        total_pages, total_items = page.get("total_pages"), page.get("total_items")
        require(type(total_pages) is int and 1 <= total_pages <= MAX_PAGES
                and type(total_items) is int and 0 <= total_items <= 100000,
                "invalid_snapshot_counts")
        require(page_number <= total_pages, "unexpected_page")
        snapshot_id = text(page.get("snapshot_id"), 1, 200, "invalid_snapshot_id")
        started = instant(page.get("snapshot_started_at"))
        require(now - timedelta(minutes=30) <= started <= now + timedelta(minutes=5),
                "stale_source_snapshot")
        metadata = (snapshot_id, page["snapshot_started_at"], total_pages, total_items)
        if expected is None:
            expected = metadata
        require(metadata == expected, "snapshot_changed_during_pagination")
        require(isinstance(page.get("items"), list), "invalid_items_array")
        for raw in page["items"]:
            item = normalize_item(raw, places, now)
            require(item["source_id"] not in ids, "duplicate_source_id")
            ids.add(item["source_id"])
            items.append(item)
            require(len(items) <= total_items, "total_item_count_mismatch")
        next_page = page.get("next")
        require("next" in page, "missing_pagination_proof")
        if page_number == total_pages:
            require(next_page is None, "unexpected_extra_page")
            if total_items == 0:
                require(allow_empty and page.get("empty_confirmed") is True,
                        "empty_snapshot_requires_operator_confirmation")
        else:
            require(isinstance(next_page, str) and bool(next_page), "missing_next_page")
            require(len(page["items"]) > 0, "empty_intermediate_page")
        current = https_url(urljoin(current, next_page)) if next_page is not None else None
        page_number += 1
    require(expected is not None and len(items) == expected[3], "total_item_count_mismatch")
    require(page_number - 1 == expected[2], "total_page_count_mismatch")
    return items, True


def run(environ: dict[str, str], *, dry_run: bool = False) -> dict:
    mode = environ.get("MYSNU_SOURCE_MODE", "portal")
    require(mode in ("export", "portal"), "invalid_source_mode")
    if mode == "portal":
        # Lazy import avoids changing the export contract or requiring a browser.
        from portal_mysnu import collect_portal, portal_reader, storage_locations
        now = datetime.now(timezone.utc)
        try:
            defaults = json.loads(Path(__file__).with_name("locations.json").read_text(encoding="utf-8"))
            checked = datetime.fromisoformat(defaults["checked_on"]).date()
            require(now.date() - timedelta(days=365) <= checked <= now.date(), "outdated_storage_verification")
            police_raw = environ.get("MYSNU_VERIFIED_POLICE_LOCATIONS") or json.dumps(defaults["police"])
            storage_raw = environ.get("MYSNU_STORAGE_LOCATIONS") or json.dumps(defaults["storage"])
            places = verified_locations(json.loads(police_raw), now)
            storage = storage_locations(storage_raw)
        except (OSError, KeyError, TypeError, ValueError) as error:
            raise SyncError("invalid_portal_location_configuration") from error
        cookie = environ.get("MYSNU_COOKIE", "")
        require(bool(cookie) and "\r" not in cookie and "\n" not in cookie, "portal_session_required")
        try:
            interval = float(environ.get("MYSNU_REQUEST_INTERVAL_SECONDS", "0.25"))
        except ValueError as error:
            raise SyncError("invalid_portal_request_interval") from error
        require(math.isfinite(interval) and 0.25 <= interval <= 10, "invalid_portal_request_interval")
        items, complete = collect_portal(portal_reader(cookie, interval), places, storage, now)
        return synchronize(items, complete, environ, dry_run=dry_run)
    url = environ.get("MYSNU_FEED_URL", "")
    require(bool(url), "mysnu_source_not_configured")
    https_url(url)
    headers = {}
    cookie = environ.get("MYSNU_COOKIE", "")
    if cookie:
        host = urlsplit(url).hostname.lower()
        require(host == "snu.ac.kr" or host.endswith(".snu.ac.kr"), "cookie_destination_not_snu")
        require("\r" not in cookie and "\n" not in cookie, "invalid_auth_header")
        headers["Cookie"] = cookie
    bearer = environ.get("MYSNU_FEED_TOKEN", "")
    if bearer:
        require("\r" not in bearer and "\n" not in bearer, "invalid_auth_header")
        headers["Authorization"] = "Bearer " + bearer
    now = datetime.now(timezone.utc)
    try:
        places = verified_locations(json.loads(environ.get("MYSNU_VERIFIED_POLICE_LOCATIONS", "[]")), now)
    except json.JSONDecodeError as error:
        raise SyncError("invalid_verified_locations_json") from error
    items, complete = collect_snapshot(url, lambda u: request_json(u, headers=headers), places, now,
        allow_empty=environ.get("MYSNU_ALLOW_CONFIRMED_EMPTY") == "true")
    return synchronize(items, complete, environ, dry_run=dry_run)


def server_configuration(environ: dict[str, str]) -> tuple[str, dict[str, str]]:
    """Validate settings before a long collection; never put a secret in a URL."""
    supabase = environ.get("SUPABASE_URL", "").rstrip("/")
    https_url(supabase)
    parsed = urlsplit(supabase)
    require(not parsed.path and not parsed.query, "invalid_supabase_origin")
    key = environ.get("SUPABASE_SECRET_KEY") or environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    require(bool(key) and "\n" not in key and "\r" not in key, "service_role_key_required")
    # Client publishable/anon credentials cannot be used by this service-only RPC.
    require(not key.startswith("sb_publishable_"), "service_role_key_required")
    headers = {"apikey": key}
    # Modern secret keys are opaque API keys, not bearer JWTs.
    if not key.startswith("sb_secret_"):
        headers["Authorization"] = "Bearer " + key
    return supabase, headers


def synchronize(items: list[dict], complete: bool, environ: dict[str, str], *, dry_run: bool) -> dict:
    result = {"items": len(items), "complete": complete, "dry_run": dry_run}
    if dry_run:
        return result
    supabase, headers = server_configuration(environ)
    response = request_json(supabase + "/rest/v1/rpc/lf_sync_mysnu", headers=headers, data={
        "p_items": items, "p_complete": complete, "p_run_id": str(uuid.uuid4())})
    require(isinstance(response, dict) and response.get("ok") is True, "sync_rpc_not_confirmed")
    result["sync"] = {name: response[name] for name in ("seen", "inserted", "updated", "removed")
                      if type(response.get(name)) is int and response[name] >= 0}
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--dry-run", action="store_true", help="Validate the source without calling Supabase (default)")
    action.add_argument("--apply", action="store_true", help="Write a validated full snapshot to Supabase")
    parser.add_argument("--source-mode", choices=("portal", "export"), help="Default: actual MySNU portal")
    parser.add_argument("--prompt-session", action="store_true", help="Enter approved credentials privately in a local terminal; never saved")
    args = parser.parse_args()
    try:
        settings = dict(os.environ)
        if args.source_mode:
            settings["MYSNU_SOURCE_MODE"] = args.source_mode
        if args.prompt_session:
            require(settings.get("MYSNU_SOURCE_MODE", "portal") == "portal", "prompt_requires_portal_mode")
            require(sys.stdin.isatty() and sys.stderr.isatty(), "interactive_terminal_required")
            if not settings.get("MYSNU_COOKIE"):
                settings["MYSNU_COOKIE"] = getpass.getpass("Approved MySNU session cookie (hidden, not saved): ")
            if args.apply and not (settings.get("SUPABASE_SECRET_KEY") or settings.get("SUPABASE_SERVICE_ROLE_KEY")):
                settings["SUPABASE_SECRET_KEY"] = getpass.getpass("Supabase server secret/service-role key (hidden, not saved): ")
        if args.apply:
            server_configuration(settings)
        result = run(settings, dry_run=not args.apply)
    except SyncError as error:
        print("Lost-found sync stopped: " + str(error), file=sys.stderr)
        return 1
    except Exception:
        # Tracebacks may contain request URLs, cookies, or source record contents.
        print("Lost-found sync stopped: unexpected_failure", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.modules["sync_mysnu"] = sys.modules[__name__]
    raise SystemExit(main())
