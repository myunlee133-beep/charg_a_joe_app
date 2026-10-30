-- Test-only transaction. ROLLBACK leaves the migrated test schema unchanged.
BEGIN;
CREATE OR REPLACE FUNCTION pg_temp.lf_assert(p_ok boolean,p_message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %',p_message; END IF; END $$;
CREATE OR REPLACE FUNCTION pg_temp.lf_expect_error(p_sql text,p_state text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text; BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
  IF v_state<>p_state THEN RAISE EXCEPTION 'Expected SQLSTATE %, got % for %',p_state,v_state,p_sql; END IF;
  RETURN;
 END;
 RAISE EXCEPTION 'Expected failure % for %',p_state,p_sql;
END $$;

DO $$
DECLARE
 author uuid:='10000000-0000-0000-0000-000000000001';
 claimant uuid:='10000000-0000-0000-0000-000000000002';
 other uuid:='10000000-0000-0000-0000-000000000003';
 moderator uuid:='10000000-0000-0000-0000-000000000004';
 observer uuid:='10000000-0000-0000-0000-000000000005';
 item uuid; claim uuid; other_claim uuid; staff_item uuid;
 race_item uuid; winner uuid; loser uuid;
 snapshot jsonb; one jsonb; result1 jsonb; result2 jsonb; mysnu_id uuid; count_before bigint;
 run1 uuid:='40000000-0000-0000-0000-000000000001';
 run2 uuid:='40000000-0000-0000-0000-000000000002';
 run3 uuid:='40000000-0000-0000-0000-000000000003';
 run4 uuid:='40000000-0000-0000-0000-000000000004';
BEGIN
 INSERT INTO auth.users(id) VALUES(other),(moderator),(observer);
 INSERT INTO public.community_profiles(user_id,nickname,role) VALUES(other,'제삼자테스트','member'),(moderator,'담당자테스트','moderator');
 PERFORM pg_temp.lf_assert((SELECT count(*)=2 FROM public.lf_found_items),'legacy found rows preserved');
 PERFORM pg_temp.lf_assert((SELECT count(*)=1 FROM public.lf_claims),'legacy claims preserved');
 PERFORM pg_temp.lf_assert((SELECT status='received' AND received_reason='legacy_closed' FROM public.lf_items WHERE id='20000000-0000-0000-0000-000000000002'),'closed legacy mapping');
 PERFORM pg_temp.lf_assert((SELECT status='accepted' AND item_id='20000000-0000-0000-0000-000000000001' FROM public.lf_item_claims WHERE id='30000000-0000-0000-0000-000000000001'),'claim ID and state migrated');
 PERFORM pg_temp.lf_assert(NOT has_function_privilege('authenticated','public.lf_lost_list()','EXECUTE'),'legacy lost RPC revoked');
 PERFORM pg_temp.lf_assert(NOT has_function_privilege('authenticated','public.lf_found_create(text,text,text,text,double precision,double precision,timestamptz,text,text)','EXECUTE'),'legacy found creation revoked');
 PERFORM pg_temp.lf_assert(NOT has_function_privilege('anon','public.lf_items_list()','EXECUTE'),'anonymous listing denied');
 PERFORM pg_temp.lf_assert(NOT has_function_privilege('authenticated','public.lf_sync_mysnu(jsonb,boolean,uuid)','EXECUTE'),'members cannot sync source');
 PERFORM pg_temp.lf_assert(has_function_privilege('service_role','public.lf_sync_mysnu(jsonb,boolean,uuid)','EXECUTE'),'service can sync');
 PERFORM pg_temp.lf_assert(NOT has_table_privilege('authenticated','public.lf_items','SELECT,INSERT,UPDATE,DELETE'),'members have no table access');
 PERFORM pg_temp.lf_assert(NOT has_table_privilege('service_role','public.lf_items','INSERT,UPDATE,DELETE'),'service writes only through RPC');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM pg_temp.lf_expect_error('SELECT public.lf_items_list()','28000');
 PERFORM set_config('request.jwt.claim.sub',author::text,true);
 PERFORM pg_temp.lf_expect_error($q$SELECT public.lf_item_create('지갑','지갑','','',37.46,126.95)$q$,'23514');
 PERFORM pg_temp.lf_expect_error($q$SELECT public.lf_item_create('지갑','지갑','','학생회관',0,126.95)$q$,'23514');
 PERFORM pg_temp.lf_expect_error($q$SELECT public.lf_item_create('지갑','지갑','','학생회관',37.46,126.95,'bm90LWpwZWc=')$q$,'22023');
 item:=public.lf_item_create('지갑','사진 있는 지갑','안쪽 특징은 확인용','학생회관',37.46,126.95,encode(decode('ffd8ff00ffd9','hex'),'base64'));
 PERFORM pg_temp.lf_assert((SELECT source='user' FROM public.lf_items WHERE id=item),'member source cannot spoof staff');
 PERFORM pg_temp.lf_assert(public.lf_item_detail(item)->>'photo_base64'='/9j/AP/Z','detail has complete photo');
 PERFORM pg_temp.lf_assert((SELECT value->'photo_base64'='null'::jsonb FROM jsonb_array_elements(public.lf_items_list()) WHERE value->>'id'=item::text),'list excludes image payload');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_claim_interest(%L,''본인이 등록한 물건입니다'')',item),'22023');
 PERFORM set_config('request.jwt.claim.sub',claimant::text,true);
 claim:=public.lf_claim_interest(item,'지갑 안쪽에 이름과 별표가 있습니다');
 PERFORM pg_temp.lf_assert(claim=public.lf_claim_interest(item,'같은 요청의 중복 네트워크 재시도'),'interest is idempotent');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_claim_complete(%L,''received'')',claim),'22023');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_claim_verify(%L,true)',claim),'42501');
 PERFORM set_config('request.jwt.claim.sub',other::text,true);
 PERFORM pg_temp.lf_assert(jsonb_array_length(public.lf_claims_list())=0,'other member cannot see ownership proof');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_claim_complete(%L,''not_mine'')',claim),'42501');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_item_transfer(%L,''관악경찰서'',37.48,126.95)',item),'42501');
 other_claim:=public.lf_claim_interest(item,'다른 요청자의 확인 가능한 고유 특징');
 PERFORM set_config('request.jwt.claim.sub',author::text,true);
 PERFORM pg_temp.lf_assert(public.lf_claim_verify(claim,true),'author verifies first claimant');
 PERFORM pg_temp.lf_assert(public.lf_claim_verify(other_claim,true),'author may verify second claim before receipt');
 PERFORM pg_temp.lf_assert(public.lf_item_transfer(item,'관악경찰서 민원실',37.48,126.95),'author records actual police destination');
 PERFORM pg_temp.lf_assert(public.lf_item_detail(item)->>'status'='police','police item remains visible');
 PERFORM set_config('request.jwt.claim.sub',other::text,true);
 PERFORM pg_temp.lf_assert(public.lf_claim_complete(other_claim,'not_received'),'nonreceipt can be reported');
 PERFORM pg_temp.lf_assert(public.lf_item_detail(item)->>'status'='police','nonreceipt never hides item');
 PERFORM set_config('request.jwt.claim.sub',claimant::text,true);
 PERFORM pg_temp.lf_assert(public.lf_claim_complete(claim,'received'),'verified claimant completes receipt');
 PERFORM pg_temp.lf_assert(public.lf_claim_complete(claim,'received'),'receipt retry is idempotent');
 PERFORM pg_temp.lf_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.lf_items_list()) WHERE value->>'id'=item::text),'received hidden from list/map');
 PERFORM set_config('request.jwt.claim.sub',moderator::text,true);
 staff_item:=public.lf_item_create('우산','담당자 습득물','','101동 분실물센터',37.46328,126.95015);
 PERFORM pg_temp.lf_assert((SELECT source='staff' FROM public.lf_items WHERE id=staff_item),'staff source from verified role');
 PERFORM set_config('request.jwt.claim.sub',observer::text,true);
 PERFORM pg_temp.lf_assert(public.lf_item_detail(item) IS NULL,'unrelated member cannot inspect closed item');
 PERFORM set_config('request.jwt.claim.sub',other::text,true);
 PERFORM pg_temp.lf_assert(NOT public.lf_claim_complete(other_claim,'received'),'competing claimant cannot complete received item');
 PERFORM set_config('request.jwt.claim.sub',author::text,true);
 race_item:=public.lf_item_create('가방','두 신청자의 가방','','학생회관',37.46,126.95);
 PERFORM set_config('request.jwt.claim.sub',claimant::text,true);
 winner:=public.lf_claim_interest(race_item,'가방 내부에 제 이름이 적혀 있습니다');
 PERFORM set_config('request.jwt.claim.sub',other::text,true);
 loser:=public.lf_claim_interest(race_item,'가방 내부의 고유 특징을 확인합니다');
 PERFORM set_config('request.jwt.claim.sub',moderator::text,true);
 PERFORM pg_temp.lf_assert(public.lf_claim_verify(winner,true),'moderator verifies first applicant');
 PERFORM pg_temp.lf_assert(public.lf_claim_verify(loser,true),'moderator verifies second applicant');
 PERFORM set_config('request.jwt.claim.sub',claimant::text,true);
 PERFORM pg_temp.lf_assert(public.lf_claim_complete(winner,'received'),'first verified receipt wins');
 PERFORM set_config('request.jwt.claim.sub',other::text,true);
 PERFORM pg_temp.lf_assert(NOT public.lf_claim_complete(loser,'received'),'later receipt cannot also win');
 PERFORM pg_temp.lf_assert((SELECT status='rejected' FROM public.lf_item_claims WHERE id=loser),'other accepted claims close after receipt');
 PERFORM pg_temp.lf_expect_error('SELECT public.lf_sync_mysnu(''[]'',true,gen_random_uuid())','42501');

 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 snapshot:=jsonb_build_array(jsonb_build_object('source_id','test-A','category','열쇠','title','외부 열쇠','description','공식 수집 항목',
  'location_name','101동 분실물센터','latitude',37.46328,'longitude',126.95015,'registered_at','2026-01-01T09:00:00+09:00','status','stored'),
  jsonb_build_object('source_id','test-B','category','우산','title','외부 우산','description','공식 수집 항목',
  'location_name','101동 분실물센터','latitude',37.46328,'longitude',126.95015,'registered_at','2026-01-02T09:00:00+09:00','status','stored'));
 result1:=public.lf_sync_mysnu(snapshot,true,run1);
 result2:=public.lf_sync_mysnu(snapshot,true,run1);
 PERFORM pg_temp.lf_assert(result1=result2 AND (result1->>'inserted')::integer=2,'run replay is idempotent');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_sync_mysnu(%L::jsonb,false,%L)',snapshot::text,run1),'22023');
 one:=jsonb_build_array(snapshot->0);
 PERFORM public.lf_sync_mysnu(one,false,run2);
 PERFORM pg_temp.lf_assert((SELECT status='stored' FROM public.lf_items WHERE source='mysnu' AND source_id='test-B'),'partial snapshot preserves missing items');
 SELECT count(*) INTO count_before FROM public.lf_items;
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_sync_mysnu(%L::jsonb,true,gen_random_uuid())',
  jsonb_build_array(snapshot->0,jsonb_set(snapshot->1,'{latitude}','0'::jsonb))::text),'22023');
 PERFORM pg_temp.lf_assert((SELECT count(*)=count_before FROM public.lf_items),'invalid complete snapshot changes nothing');
 PERFORM pg_temp.lf_assert(NOT EXISTS(SELECT 1 FROM public.lf_items WHERE source='mysnu' AND status='received'),'failed snapshot never infers disappearance');
 PERFORM public.lf_sync_mysnu(one,true,run3);
 PERFORM pg_temp.lf_assert((SELECT status='received' AND received_reason='source_removed' FROM public.lf_items WHERE source='mysnu' AND source_id='test-B'),'complete absence records source removal');
 PERFORM public.lf_sync_mysnu(snapshot,true,run4);
 PERFORM pg_temp.lf_assert((SELECT status='received' FROM public.lf_items WHERE source='mysnu' AND source_id='test-B'),'source reappearance cannot reopen tombstone');
 PERFORM pg_temp.lf_expect_error('SELECT public.lf_sync_mysnu(''[]'',true,gen_random_uuid())','22023');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_sync_mysnu(%L::jsonb,true,gen_random_uuid())',
  jsonb_build_array(snapshot->0,snapshot->0)::text),'22023');
 PERFORM pg_temp.lf_expect_error(format('SELECT public.lf_sync_mysnu(%L::jsonb,true,gen_random_uuid())',
  jsonb_build_array(jsonb_set(snapshot->1,'{location_name}','""'::jsonb))::text),'22023');
 PERFORM pg_temp.lf_assert((SELECT count(*)=1 FROM public.lf_sync_runs WHERE run_id=run1),'one log record per run');
 PERFORM pg_temp.lf_assert((SELECT count(*)=2 FROM public.lf_found_items),'all legacy source records remain archived');
 RAISE NOTICE 'Unified found-items regression assertions passed';
END $$;
ROLLBACK;
