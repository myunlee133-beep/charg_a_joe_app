"""Daily observed service/break time hints, distinct from standard operating hours."""
from __future__ import annotations
import hashlib
import re

TIME_RANGE = re.compile(r'(?<!\d)(\d{1,2})\s*:\s*(\d{2})\s*[~～〜\-]\s*(\d{1,2})\s*:\s*(\d{2})')


def normalized_hours(text: str) -> str:
    def substitute(m):
        a,b,c,d=map(int,m.groups())
        if not (0<=a<24 and 0<=c<24 and 0<=b<60 and 0<=d<60):
            return m.group(0)
        return f'{a:02d}:{b:02d}-{c:02d}:{d:02d}'
    return TIME_RANGE.sub(substitute,text)


def extract_service_hours(observations: list[dict]) -> list[dict]:
    """Do not infer weekday hours from a dated meal. Preserve notices as observations."""
    seen=set();results=[]
    for r in observations:
        text=r.get('raw_text','')
        if not any(x in text for x in ('운영시간','운영 시간','브레이크타임','Break time','라스트 오더','라스트오더','이용시간','준비수량','예약')):
            continue
        unit=r.get('restaurant_unit') or r['restaurant']
        identity=(r['source_date'],unit,r['meal_type'],text)
        if identity in seen:continue
        seen.add(identity)
        results.append({'source_date':r['source_date'],'restaurant_unit':unit,
            'meal_type':r['meal_type'],'raw_notice':text,
            'normalized_notice':normalized_hours(text),'source':r['source'],
            'source_url':r.get('source_url','')})
    return results
