-- Disposable synthetic actors only; always rolled back. Run as postgres after the migrations.
begin;
do $$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 q uuid; p uuid; t uuid; q2 uuid; pb uuid; pc uuid; t2 uuid; blocked boolean; versions jsonb; value jsonb; before_count integer;
begin
 if exists(select 1 from public.account_policy_versions where encode(pg_catalog.sha256(convert_to(body,'UTF8')),'hex')<>sha256) then raise exception 'FAIL: policy content hash mismatch'; end if;
 insert into auth.users(id,email,email_confirmed_at) values
 (a,a::text||'@example.invalid',now()),(b,b::text||'@example.invalid',now()),(c,c::text||'@example.invalid',now());
 select jsonb_object_agg(kind,version) into versions from public.account_policy_versions where active;
 perform set_config('request.jwt.claim.sub',a::text,true);
 blocked:=false;
 begin perform public.quest_create('테스트 의뢰','의뢰 상세 내용은 충분한 길이로 작성합니다','errand','firstCome',3000,'학생회관','63동',37.45925,126.9506);
 exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: incomplete onboarding accepted'; end if;
 perform public.account_complete_onboarding('검증A_'||substr(a::text,1,8),versions,true);
 perform public.account_accept_policies(versions,'transaction');
 q:=public.quest_create('테스트 의뢰','의뢰 상세 내용은 충분한 길이로 작성합니다','errand','firstCome',3000,'학생회관','63동',37.45925,126.9506);
 blocked:=false; begin perform public.quest_accept(q); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: requester accepted own quest'; end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 perform public.account_complete_onboarding('검증B_'||substr(b::text,1,8),versions,true);
 perform public.account_accept_policies(versions,'transaction');
 p:=public.quest_accept(q);
 blocked:=false; begin perform public.quest_submit(q,null); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: null submission accepted'; end if;
 perform public.quest_submit(q,'작업을 완료했습니다. 학생회관 안내 장소를 확인해 주세요.');
 blocked:=false; begin perform public.quest_review(p,true); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: performer approved own result'; end if;

 perform set_config('request.jwt.claim.sub',c::text,true);
 perform public.account_complete_onboarding('검증C_'||substr(c::text,1,8),versions,true);
 perform public.account_accept_policies(versions,'transaction');
 blocked:=false; begin perform public.quest_accept(q); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: second first-come acceptance succeeded'; end if;
 if exists(select 1 from public.quest_results(q)) then raise exception 'FAIL: third party read private results'; end if;

 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.quest_review(p,true);
 select id into t from private.quest_transactions where quest_id=q;
 blocked:=false; begin perform public.quest_dispute(t,null); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: null dispute accepted'; end if;
 if (select amount from private.quest_transactions where id=t)<>3000 then raise exception 'FAIL: reward not sourced from quest'; end if;
 blocked:=false; begin perform public.quest_review(p,true); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: duplicate reward approved'; end if;
 blocked:=false; begin perform public.quest_transfer_confirm(t); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: payer confirmed receipt'; end if;
 blocked:=false; begin delete from auth.users where id=a; exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: unresolved transaction deleted'; end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 blocked:=false; begin perform public.quest_transfer_report(t); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: payee reported payer transfer'; end if;
 blocked:=false; begin perform public.quest_save_transfer_details(t,'검증은행','검증자','000000000000',versions->>'transfer_disclosure',false); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: bank disclosure without consent'; end if;
 perform public.quest_save_transfer_details(t,'검증은행','검증자','000000000000',versions->>'transfer_disclosure',true);
 perform set_config('request.jwt.claim.sub',c::text,true);
 blocked:=false; begin perform public.quest_transfer_details(t); exception when others then blocked:=true; end;
 if not blocked then raise exception 'FAIL: third party bank disclosure'; end if;
 if exists(select 1 from public.quest_my_transactions()) then raise exception 'FAIL: third party transaction listing'; end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 if public.quest_transfer_details(t)->>'account_number'<>'000000000000' then raise exception 'FAIL: intended payer cannot see consented instructions'; end if;
 perform public.quest_transfer_report(t);
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform public.quest_transfer_confirm(t);
 -- Result reward mode permits several submissions but exactly one approved reward.
 perform set_config('request.jwt.claim.sub',a::text,true);
 q2:=public.quest_create('결과 보상 검증','분실물 발견 결과를 확인하는 합성 검증 의뢰입니다','lost','resultReward',5000,'학생회관','63동',37.45925,126.9506);
 perform set_config('request.jwt.claim.sub',b::text,true);
 pb:=public.quest_submit(q2,'첫 번째 합성 결과입니다. 발견 장소와 특징을 전달합니다.');
 perform set_config('request.jwt.claim.sub',c::text,true);
 pc:=public.quest_submit(q2,'두 번째 합성 결과입니다. 발견 장소와 특징을 전달합니다.');
 if (select count(*) from public.quest_results(q2))<>1 then raise exception 'FAIL: performer saw another submission'; end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 if (select count(*) from public.quest_results(q2))<>2 then raise exception 'FAIL: requester could not review both results'; end if;
 perform public.quest_review(pc,true);
 blocked:=false; begin perform public.quest_review(pb,true); exception when others then blocked:=true; end;
 if not blocked or (select count(*) from private.quest_transactions where quest_id=q2)<>1 then raise exception 'FAIL: multiple result rewards approved'; end if;
 select id into t2 from private.quest_transactions where quest_id=q2;
 perform set_config('request.jwt.claim.sub',c::text,true);
 perform public.quest_save_transfer_details(t2,'검증은행','검증자','000000000002',versions->>'transfer_disclosure',true);
 perform set_config('request.jwt.claim.sub',a::text,true); perform public.quest_transfer_report(t2);
 perform set_config('request.jwt.claim.sub',c::text,true); perform public.quest_transfer_confirm(t2);
 update private.quest_transfer_details set delete_after=now()-interval '1 second' where transaction_id=t2;
 update private.quest_transactions set received_at=now()-interval '31 days' where id=t2;
 perform private.account_purge_expired();
 if exists(select 1 from private.quest_transfer_details where transaction_id=t2) then raise exception 'FAIL: expired bank instructions retained'; end if;
 if exists(select 1 from public.quest_participations where quest_id=q2 and result_text is not null) then raise exception 'FAIL: expired result text retained'; end if;
 if not exists(select 1 from private.quest_transactions where id=t2) then raise exception 'FAIL: early ledger erasure'; end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 select count(*) into before_count from private.quest_transactions where id=t;
 perform public.account_delete('찾아줘 계정 삭제');
 if exists(select 1 from auth.users where id=b) then raise exception 'FAIL: account not deleted'; end if;
 if (select count(*) from private.quest_transactions where id=t)<>before_count then raise exception 'FAIL: account deletion cascaded to ledger'; end if;
 if exists(select 1 from private.quest_transfer_details where transaction_id=t) then raise exception 'FAIL: bank detail survived deletion'; end if;
 if exists(select 1 from private.quest_transactions where id=t and payee_user_id is not null) then raise exception 'FAIL: retained login identity link'; end if;

 if has_table_privilege('anon','public.quests','SELECT') or has_table_privilege('authenticated','public.quests','UPDATE')
 or has_schema_privilege('authenticated','private','USAGE') then raise exception 'FAIL: direct data access granted'; end if;
 if has_function_privilege('anon','public.quest_accept(uuid)','EXECUTE') then raise exception 'FAIL: anon write RPC granted'; end if;
 if not has_function_privilege('anon','public.quest_feed(boolean)','EXECUTE') then raise exception 'FAIL: public feed inaccessible'; end if;
 perform set_config('request.jwt.claim.sub','',true);
 select x into value from public.quest_feed(false) x limit 1;
 if value is not null and (value ? 'requester_user_id' or value ? 'email' or value ? 'account_number') then raise exception 'FAIL: public identity/financial disclosure'; end if;
 raise notice 'PASS: onboarding, ownership, first-come exclusivity, result privacy, unique result reward, amount authority, payment actors, bank consent, expiry, account deletion retention and grants';
end $$;
rollback;
