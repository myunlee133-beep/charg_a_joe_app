-- Add the shuttle custody point without changing roles, grants or RLS.
-- Campus-map building 331 coordinates; the custody guidance is historical (2014).
BEGIN;
INSERT INTO public.lf_centers
(id,name,building,room,latitude,longitude,phone,weekday_hours,weekend_holiday_note,custody_note,source_url,checked_on)
VALUES
('snu331','서울대 셔틀버스 분실물 보관소','331동 차량정비고','차량고 보관처 · 방문 전 확인',37.44937,126.95014,NULL,NULL,
 '현재 운영시간·휴무일 미확인: 셔틀버스 담당 부서에 방문 전 확인',
 '2014년 공식 안내의 셔틀버스 습득물 임시 보관처입니다. 당시에는 해당 주간 차량고 보관 후 학생지원센터로 이관했으며 현재 보관처·이관 일정은 재확인이 필요합니다.',
 'https://aerospace.snu.ac.kr/board/notice?bbsidx=23230&bm=v','2026-10-31')
ON CONFLICT (id) DO UPDATE SET
 name=excluded.name,building=excluded.building,room=excluded.room,
 latitude=excluded.latitude,longitude=excluded.longitude,phone=excluded.phone,
 weekday_hours=excluded.weekday_hours,weekend_holiday_note=excluded.weekend_holiday_note,
 custody_note=excluded.custody_note,source_url=excluded.source_url,checked_on=excluded.checked_on;
COMMIT;
