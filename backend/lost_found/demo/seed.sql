-- Administrator-only, opt-in test data. Never run as a schema migration.
-- In the SAME transaction, set chajajwo.demo_owner_id to an existing test user's UUID.
-- BEGIN; SELECT set_config('chajajwo.demo_owner_id','<test-user-uuid>',true);
-- [this file] COMMIT;
-- 16 items: 13 stored, 2 police, 1 received. All are explicitly fictional.
DO $seed$
DECLARE
 owner_id uuid := nullif(current_setting('chajajwo.demo_owner_id',true),'')::uuid;
 dataset constant text := 'lost-found-demo-v1';
BEGIN
 IF owner_id IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=owner_id) THEN
  RAISE EXCEPTION 'Set chajajwo.demo_owner_id to an existing test user first';
 END IF;
 IF EXISTS (
  SELECT 1 FROM public.lf_items i
  WHERE i.id IN (SELECT ('d3f00000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid FROM generate_series(1,16) n)
    AND NOT EXISTS(SELECT 1 FROM public.lf_item_events e WHERE e.item_id=i.id
                   AND e.kind='demo_seed' AND e.detail->>'dataset'=dataset)
 ) THEN
  RAISE EXCEPTION 'Demo ID collision: existing records were not changed';
 END IF;
 WITH samples(n,category,title,description,location_name,latitude,longitude,status) AS (VALUES
  (1,'지갑','검정 반지갑','안쪽에 별 모양 스티커가 있는 가상 지갑','101동 아시아연구소 1층 · 가상 보관함',37.46328,126.95015,'stored'),
  (2,'전자기기','흰색 무선 이어폰','연두색 실리콘 케이스를 씌운 가상 이어폰','101동 아시아연구소 1층 · 가상 보관함',37.46328,126.95015,'stored'),
  (3,'학생증','파란 학생증 케이스','이름·학번이 없는 가상 학생증 케이스','101동 아시아연구소 1층 · 가상 보관함',37.46328,126.95015,'stored'),
  (4,'우산','남색 장우산','손잡이에 흰색 끈이 달린 가상 우산','101동 아시아연구소 1층 · 가상 보관함',37.46328,126.95015,'stored'),
  (5,'열쇠','곰돌이 키링 열쇠','실제 문을 열 수 없는 모형 열쇠','101동 아시아연구소 1층 · 가상 보관함',37.46328,126.95015,'stored'),
  (6,'가방','회색 파우치','빈 가상 파우치','101동 아시아연구소 1층 · 가상 보관함',37.46328,126.95015,'stored'),
  (7,'의류','검정 모자','별 그림이 새겨진 가상 모자','67동 두레문예관 · 가상 보관함',37.46353,126.94973,'stored'),
  (8,'기타','보라색 물병','뚜껑에 노란 띠가 있는 가상 물병','67동 두레문예관 · 가상 보관함',37.46353,126.94973,'stored'),
  (9,'전자기기','휴대용 충전기','전원이 들어오지 않는 가상 충전기','67동 두레문예관 · 가상 보관함',37.46353,126.94973,'stored'),
  (10,'우산','접이식 우산','줄무늬 덮개가 있는 가상 우산','63동 학생회관 · 가상 보관함',37.45932,126.95058,'stored'),
  (11,'의류','초록색 목도리','체크무늬 가상 목도리','63동 학생회관 · 가상 보관함',37.45932,126.95058,'stored'),
  (12,'가방','갈색 책가방','내용물이 없는 가상 책가방','62동 중앙도서관 · 가상 보관함',37.45940,126.95199,'stored'),
  (13,'기타','노란색 필통','연필 두 자루가 있는 가상 필통','301동 신공학관 · 가상 보관함',37.45016,126.95259,'stored'),
  (14,'지갑','경찰 이관 지갑','경찰서 이관 상태를 확인하는 가상 물품','관악경찰서 · 가상 보관함 (테스트)',37.47458392608702,126.95105330444076,'police'),
  (15,'전자기기','경찰 이관 태블릿','경찰서 이관 위치를 확인하는 가상 물품','관악경찰서 · 가상 보관함 (테스트)',37.47458392608702,126.95105330444076,'police'),
  (16,'열쇠','수령 완료 열쇠','목록·지도에서 보이지 않아야 하는 가상 물품','101동 아시아연구소 1층 · 가상 보관함',37.46328,126.95015,'received')
 ), added AS (
  INSERT INTO public.lf_items(id,source,author_id,category,title,description,location_name,latitude,longitude,registered_at,status,received_reason)
  SELECT ('d3f00000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'user',owner_id,category,
         '[테스트] '||title,'[화면 확인용 가상 데이터 · 실제 분실물이 아닙니다] '||description,
         location_name,latitude,longitude,now()-make_interval(days=>n-1),status,
         CASE WHEN status='received' THEN 'legacy_closed' ELSE NULL END
  FROM samples ON CONFLICT(id) DO NOTHING RETURNING id
 )
 INSERT INTO public.lf_item_events(item_id,actor_id,kind,detail)
 SELECT id,owner_id,'demo_seed',jsonb_build_object('dataset',dataset,'fictional',true) FROM added;
END $seed$;

SELECT i.status,count(*) AS demo_items FROM public.lf_items i
WHERE EXISTS(SELECT 1 FROM public.lf_item_events e WHERE e.item_id=i.id
             AND e.kind='demo_seed' AND e.detail->>'dataset'='lost-found-demo-v1')
GROUP BY i.status ORDER BY i.status;
