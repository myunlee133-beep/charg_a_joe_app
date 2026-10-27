"""Conservative HTTP fetcher: HTTPS verification, timeouts and low request rate."""
from __future__ import annotations

import time
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from urllib.parse import urlsplit

USER_AGENT = "ChajwoIndependentMealCrawler/0.3.1 (+project-maintainer-contact-required)"


class RateLimitedFetcher:
    def __init__(self, *, min_interval: float = 2.0, timeout: float = 15.0, session=None):
        if min_interval < 0.5 or timeout <= 0:
            raise ValueError("min_interval must be >=0.5 and timeout positive")
        self.interval = min_interval
        self.timeout = timeout
        self.session = session or requests.Session()
        if session is None:
            retry = Retry(total=2, backoff_factor=1.0, status_forcelist=(429, 500, 502, 503, 504),
                          allowed_methods=frozenset(("GET",)), respect_retry_after_header=True)
            self.session.mount("https://", HTTPAdapter(max_retries=retry))
        self.last_request = None

    def get(self, url: str) -> str:
        if not url.startswith("https://"):
            raise ValueError("Only HTTPS sources are supported")
        if self.last_request is not None:
            elapsed = time.monotonic() - self.last_request
            if elapsed < self.interval:
                time.sleep(self.interval - elapsed)
        self.last_request = time.monotonic()
        res = self.session.get(url, timeout=self.timeout, headers={"User-Agent": USER_AGENT},
                               verify=True, allow_redirects=True)
        res.raise_for_status()
        if urlsplit(res.url).netloc != urlsplit(url).netloc:
            raise ValueError("Unexpected redirect to another host")
        # The SNU campus-map JSON can be EUC-KR, not UTF-8. Requests'
        # apparent_encoding is statistical and may garble Korean building names.
        # A true UTF-8 response must still take precedence.
        if urlsplit(url).path == "/api/building.action":
            raw = res.content
            try:
                return raw.decode("utf-8-sig")
            except UnicodeDecodeError:
                return raw.decode("euc-kr")
        if not res.encoding or res.encoding.upper() == "ISO-8859-1":
            res.encoding = res.apparent_encoding or "utf-8"
        return res.text
