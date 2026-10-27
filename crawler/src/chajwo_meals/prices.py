"""Conservative Korean-won price normalization.

The *only* automatic trailing-zero correction is for invalid groupings like
'8,3000원' -> '8,300원' (8,300 won). Proper prices such as '10,000원'
are never modified. The raw original is always retained for audit.
"""
from __future__ import annotations
import re

TOKEN = re.compile(r'(?<![\d.,])([0-9][0-9.,]*)\s*원')
VALID_COMMA = re.compile(r'^\d{1,3}(?:,\d{3})+$')
VALID_DOT = re.compile(r'^\d{1,3}(?:\.\d{3})+$')


def parse_won(token: str) -> tuple[int | None, str, str]:
    raw = token.strip()
    if raw.isdecimal() and 1 <= len(raw) <= 7:
        value = int(raw)
        return (value, 'as_published', raw) if 100 <= value <= 200000 else (None, 'needs_review', raw)
    if VALID_COMMA.fullmatch(raw):
        return int(raw.replace(',','')), 'as_published', raw
    if VALID_DOT.fullmatch(raw):
        return int(raw.replace('.','')), 'dot_thousands_normalized', raw
    if ',' in raw and '.' not in raw:
        bits = raw.split(',')
        if 1 <= len(bits[0]) <= 3 and bits[0].isdigit() and all(b.isdigit() for b in bits[1:]):
            last = bits[-1]
            # Last grouping can have ONE OR TWO extra trailing zeros.
            if len(last) in (4, 5) and last.endswith('0' * (len(last)-3)):
                fixed = ','.join(bits[:-1] + [last[:3]])
                if VALID_COMMA.fullmatch(fixed):
                    return int(fixed.replace(',','')), 'trailing_zero_corrected', fixed
    return None, 'needs_review', raw


def parse_price_text(text: str) -> tuple[int | None, str, str, bool]:
    matches = list(TOKEN.finditer(text))
    if len(matches) != 1:
        return None, ('multiple_prices' if matches else 'no_price'), '', len(matches)>1
    value, status, corrected = parse_won(matches[0].group(1))
    # Unknown scattered numerals or bad price format must never be partially read.
    return value, status, matches[0].group(0), value is None
