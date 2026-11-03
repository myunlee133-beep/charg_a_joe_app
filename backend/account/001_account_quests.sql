-- 찾아줘: shared auth.users identity, versioned consent and direct-transfer quests.
-- Additive migration for project iqalavbntvadqawkegfa. Never accepts a client user_id.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.account_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 adult_confirmed_at timestamptz,
 onboarding_completed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists private.account_subjects (
 id uuid primary key default gen_random_uuid(),
 user_id uuid unique references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 closed_at timestamptz
);
create table if not exists public.account_policy_versions (
 kind text not null check(kind in ('terms','privacy','overseas','transaction','transfer_disclosure')),
 version text not null, title text not null, body text not null,
 sha256 text not null check(length(sha256)=64),
 context text not null check(context in ('account','transaction','transfer')),
 effective_at timestamptz not null, active boolean not null default true,
 primary key(kind,version)
);
create unique index if not exists account_policy_one_active on public.account_policy_versions(kind) where active;
create table if not exists private.account_consents (
 id uuid primary key default gen_random_uuid(),
 subject_id uuid not null references private.account_subjects(id),
 user_id uuid references auth.users(id) on delete set null,
 kind text not null, version text not null, document_sha256 text not null,
 accepted_at timestamptz not null default now(),
 foreign key(kind,version) references public.account_policy_versions(kind,version),
 unique(subject_id,kind,version)
);
create table if not exists public.quests (
 id uuid primary key default gen_random_uuid(),
 requester_user_id uuid references auth.users(id) on delete set null,
 requester_subject_id uuid not null references private.account_subjects(id),
 title text not null check(char_length(btrim(title)) between 2 and 120),
 details text not null check(char_length(btrim(details)) between 10 and 4000),
 category text not null check(category in ('printDelivery','lost','errand')),
 mode text not null check(mode in ('firstCome','resultReward')),
 reward integer not null check(reward between 1 and 1000000),
 place text not null check(char_length(place) between 1 and 100),
 building text not null check(char_length(building) between 1 and 150),
 latitude double precision not null check(latitude between 37.43 and 37.49),
 longitude double precision not null check(longitude between 126.92 and 126.98),
 status text not null default 'open' check(status in ('open','assigned','awaiting_transfer','transfer_reported','completed','cancelled','disputed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists quests_feed on public.quests(status,created_at desc);
create index if not exists quests_requester on public.quests(requester_user_id,created_at desc);
create table if not exists public.quest_participations (
 id uuid primary key default gen_random_uuid(), quest_id uuid not null references public.quests(id),
 performer_user_id uuid references auth.users(id) on delete set null,
 performer_subject_id uuid not null references private.account_subjects(id),
 status text not null check(status in ('accepted','submitted','approved','rejected','withdrawn')),
 result_text text check(result_text is null or char_length(btrim(result_text)) between 10 and 2000),
 created_at timestamptz not null default now(), submitted_at timestamptz,
 unique(quest_id,performer_subject_id)
);
create index if not exists quest_participations_user on public.quest_participations(performer_user_id,quest_id);
create unique index if not exists quest_one_approved on public.quest_participations(quest_id) where status='approved';
create table if not exists private.quest_transactions (
 id uuid primary key default gen_random_uuid(), quest_id uuid not null unique references public.quests(id),
 participation_id uuid not null unique references public.quest_participations(id),
 payer_user_id uuid references auth.users(id) on delete set null,
 payee_user_id uuid references auth.users(id) on delete set null,
 payer_subject_id uuid not null references private.account_subjects(id),
 payee_subject_id uuid not null references private.account_subjects(id),
 amount integer not null check(amount between 1 and 1000000), currency text not null default 'KRW' check(currency='KRW'),
 method text not null default 'direct_bank_transfer' check(method='direct_bank_transfer'),
 status text not null default 'awaiting_transfer' check(status in ('awaiting_transfer','transfer_reported','received','disputed')),
 created_at timestamptz not null default now(), reported_at timestamptz, received_at timestamptz,
 retain_until timestamptz not null default (now()+interval '5 years'),
 check(payer_subject_id<>payee_subject_id)
);
create index if not exists quest_transactions_payer on private.quest_transactions(payer_user_id);
create index if not exists quest_transactions_payee on private.quest_transactions(payee_user_id);
create table if not exists private.quest_transfer_details (
 transaction_id uuid primary key references private.quest_transactions(id),
 bank_name text not null check(char_length(bank_name) between 2 and 30),
 holder_name text not null check(char_length(holder_name) between 2 and 50),
 account_number text not null check(account_number ~ '^[0-9]{6,20}$'),
 shared_at timestamptz not null default now(), delete_after timestamptz
);
create table if not exists private.quest_events (
 id bigint generated always as identity primary key,
 quest_id uuid not null references public.quests(id),
 actor_subject_id uuid not null references private.account_subjects(id),
 event text not null, note text,
 created_at timestamptz not null default now()
);

-- Both table grants and RLS deny clients; only the explicitly granted RPCs below expose data.
do $$ declare t record; begin
 for t in select schemaname,tablename from pg_tables where
 (schemaname='public' and tablename in ('account_profiles','account_policy_versions','quests','quest_participations')) or
 (schemaname='private' and tablename in ('account_subjects','account_consents','quest_transactions','quest_transfer_details','quest_events')) loop
  execute format('alter table %I.%I enable row level security',t.schemaname,t.tablename);
  execute format('revoke all on table %I.%I from public,anon,authenticated',t.schemaname,t.tablename);
 end loop;
end $$;

create or replace function private.account_subject() returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); s uuid;
begin
 if u is null or not exists(select 1 from auth.users where id=u) then raise exception '로그인이 필요합니다' using errcode='28000'; end if;
 insert into private.account_subjects(user_id) values(u) on conflict(user_id) do nothing;
 select id into s from private.account_subjects where user_id=u;
 insert into public.account_profiles(user_id) values(u) on conflict(user_id) do nothing;
 return s;
end $$;

create or replace function public.account_policies() returns setof jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('kind',kind,'version',version,'title',title,'body',body,'sha256',sha256,'context',context)
 from public.account_policy_versions where active and effective_at<=now() order by kind;
$$;

create or replace function private.account_has_consents(p_context text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.account_policy_versions where context=p_context and active and effective_at<=now())
 and not exists(select 1 from public.account_policy_versions v where v.context=p_context and v.active and v.effective_at<=now()
 and not exists(select 1 from private.account_consents c where c.user_id=auth.uid() and c.kind=v.kind and c.version=v.version and c.document_sha256=v.sha256));
$$;

create or replace function public.account_me() returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.account_profiles%rowtype; n public.community_profiles%rowtype;
begin
 perform private.account_subject(); perform public.community_ensure_profile();
 select * into p from public.account_profiles where user_id=auth.uid();
 select * into n from public.community_profiles where user_id=auth.uid();
 return jsonb_build_object('user_id',p.user_id,'nickname',n.nickname,'role',n.role,
 'ready',p.adult_confirmed_at is not null and p.onboarding_completed_at is not null and private.account_has_consents('account'),
 'transaction_consent',private.account_has_consents('transaction'));
end $$;

create or replace function public.account_accept_policies(p_versions jsonb,p_context text) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_subject(); v record;
begin
 if p_context not in ('account','transaction','transfer') then raise exception '동의 종류가 올바르지 않습니다'; end if;
 if not exists(select 1 from public.account_policy_versions where active and context=p_context and effective_at<=now()) then
  raise exception '동의 문서가 준비되지 않았습니다'; end if;
 for v in select * from public.account_policy_versions where active and context=p_context and effective_at<=now() loop
  if p_versions->>v.kind is distinct from v.version then raise exception '최신 % 문서를 확인해 주세요',v.title; end if;
  insert into private.account_consents(subject_id,user_id,kind,version,document_sha256)
  values(s,auth.uid(),v.kind,v.version,v.sha256) on conflict(subject_id,kind,version) do nothing;
 end loop;
 return true;
end $$;

create or replace function public.account_complete_onboarding(p_nickname text,p_versions jsonb,p_adult boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform private.account_subject();
 if p_adult is distinct from true then raise exception '만 19세 이상 확인이 필요합니다'; end if;
 perform public.account_accept_policies(p_versions,'account');
 perform public.community_set_nickname(p_nickname);
 update public.account_profiles set adult_confirmed_at=coalesce(adult_confirmed_at,now()),onboarding_completed_at=now() where user_id=auth.uid();
 return public.account_me();
end $$;

create or replace function private.account_require_ready(p_transaction boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_subject();
begin
 if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception '이메일 인증이 필요합니다'; end if;
 if not exists(select 1 from public.account_profiles where user_id=auth.uid() and adult_confirmed_at is not null and onboarding_completed_at is not null)
 or not private.account_has_consents('account') then raise exception '닉네임과 필수 동의 설정을 완료해 주세요'; end if;
 if p_transaction and not private.account_has_consents('transaction') then raise exception '퀘스트 거래 약관 확인이 필요합니다'; end if;
 return s;
end $$;

create or replace function public.quest_feed(p_mine boolean default false) returns setof jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',q.id,'title',q.title,'details',q.details,'category',q.category,'mode',q.mode,'reward',q.reward,
 'place',q.place,'building',q.building,'coordinate',jsonb_build_object('latitude',q.latitude,'longitude',q.longitude),
 'distance',round(6371000*2*asin(least(1,sqrt(power(sin(radians(q.latitude-37.45925)/2),2)+cos(radians(37.45925))*cos(radians(q.latitude))*power(sin(radians(q.longitude-126.9506)/2),2))))),
 'requester',coalesce(n.nickname,'탈퇴한 사용자'),'participants',(select count(*) from public.quest_participations p where p.quest_id=q.id and p.status<>'withdrawn'),
 'status',q.status,'is_mine',coalesce(q.requester_user_id=auth.uid(),false),
 'my_participation_id',(select id from public.quest_participations p where p.quest_id=q.id and p.performer_user_id=auth.uid()),
 'my_participation_status',(select status from public.quest_participations p where p.quest_id=q.id and p.performer_user_id=auth.uid()))
 from public.quests q left join public.community_profiles n on n.user_id=q.requester_user_id
 where (not p_mine and q.status in ('open','assigned')) or (p_mine and auth.uid() is not null and
 (q.requester_user_id=auth.uid() or exists(select 1 from public.quest_participations p where p.quest_id=q.id and p.performer_user_id=auth.uid())))
 order by q.created_at desc limit 200;
$$;

create or replace function public.quest_create(p_title text,p_details text,p_category text,p_mode text,p_reward integer,p_place text,p_building text,p_latitude double precision,p_longitude double precision) returns uuid
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(true); i uuid;
begin
 if (select count(*) from public.quests where requester_user_id=auth.uid() and created_at>now()-interval '1 hour')>=20 then raise exception '등록 요청이 많습니다. 잠시 후 다시 시도해 주세요'; end if;
 insert into public.quests(requester_user_id,requester_subject_id,title,details,category,mode,reward,place,building,latitude,longitude)
 values(auth.uid(),s,btrim(p_title),btrim(p_details),p_category,p_mode,p_reward,p_place,p_building,p_latitude,p_longitude) returning id into i;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(i,s,'created'); return i;
end $$;

create or replace function public.quest_accept(p_quest_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(true); q public.quests%rowtype; i uuid;
begin
 select * into q from public.quests where id=p_quest_id for update;
 if not found or q.status<>'open' or q.mode<>'firstCome' or q.requester_user_id=auth.uid() or q.requester_user_id is null then raise exception '수락할 수 없는 퀘스트입니다'; end if;
 insert into public.quest_participations(quest_id,performer_user_id,performer_subject_id,status) values(q.id,auth.uid(),s,'accepted') returning id into i;
 update public.quests set status='assigned',updated_at=now() where id=q.id;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(q.id,s,'accepted'); return i;
end $$;

create or replace function public.quest_submit(p_quest_id uuid,p_result text) returns uuid
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(true); q public.quests%rowtype; p public.quest_participations%rowtype; i uuid;
begin
 select * into q from public.quests where id=p_quest_id for update;
 if not found or q.requester_user_id=auth.uid() or q.requester_user_id is null or q.status not in ('open','assigned') then raise exception '결과를 제출할 수 없습니다'; end if;
 if char_length(btrim(p_result)) not between 10 and 2000 then raise exception '결과를 10~2000자로 입력해 주세요'; end if;
 select * into p from public.quest_participations where quest_id=q.id and performer_subject_id=s;
 if q.mode='firstCome' and (p.id is null or p.status not in ('accepted','rejected') or q.status<>'assigned') then raise exception '수락한 수행자만 제출할 수 있습니다'; end if;
 if q.mode='resultReward' and q.status<>'open' then raise exception '이미 종료된 퀘스트입니다'; end if;
 if p.id is not null and p.status not in ('accepted','rejected') then raise exception '이미 제출한 결과입니다'; end if;
 insert into public.quest_participations(quest_id,performer_user_id,performer_subject_id,status,result_text,submitted_at)
 values(q.id,auth.uid(),s,'submitted',btrim(p_result),now())
 on conflict(quest_id,performer_subject_id) do update set status='submitted',result_text=excluded.result_text,submitted_at=now() returning id into i;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(q.id,s,'submitted'); return i;
end $$;

create or replace function public.quest_results(p_quest_id uuid) returns setof jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'nickname',coalesce(n.nickname,'탈퇴한 사용자'),'status',p.status,'result_text',p.result_text)
 from public.quest_participations p join public.quests q on q.id=p.quest_id
 left join public.community_profiles n on n.user_id=p.performer_user_id
 where q.id=p_quest_id and auth.uid() is not null and (q.requester_user_id=auth.uid() or p.performer_user_id=auth.uid())
 order by p.created_at;
$$;

create or replace function public.quest_review(p_participation_id uuid,p_accept boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(true); q public.quests%rowtype; p public.quest_participations%rowtype;
begin
 select q0.* into q from public.quests q0 join public.quest_participations p0 on p0.quest_id=q0.id where p0.id=p_participation_id for update of q0;
 select * into p from public.quest_participations where id=p_participation_id;
 if q.id is null or q.requester_user_id is distinct from auth.uid() or q.status not in ('open','assigned') or p.status<>'submitted' or p.performer_user_id is null then raise exception '결과를 확인할 권한이 없거나 이미 처리되었습니다'; end if;
 if p_accept then
  update public.quest_participations set status=case when id=p.id then 'approved' else 'rejected' end where quest_id=q.id;
  insert into private.quest_transactions(quest_id,participation_id,payer_user_id,payee_user_id,payer_subject_id,payee_subject_id,amount)
  values(q.id,p.id,auth.uid(),p.performer_user_id,s,p.performer_subject_id,q.reward);
  update public.quests set status='awaiting_transfer',updated_at=now() where id=q.id;
 else update public.quest_participations set status='rejected' where id=p.id; end if;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(q.id,s,case when p_accept then 'result_approved' else 'result_rejected' end);
 return true;
end $$;

create or replace function public.quest_my_transactions() returns setof jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',t.id,'quest_id',q.id,'title',q.title,'amount',t.amount,'status',t.status,
 'am_payer',t.payer_user_id=auth.uid(),'counterparty',coalesce(n.nickname,'탈퇴한 사용자'),'created_at',t.created_at,
 'has_transfer_details',exists(select 1 from private.quest_transfer_details d where d.transaction_id=t.id and (d.delete_after is null or d.delete_after>now())))
 from private.quest_transactions t join public.quests q on q.id=t.quest_id
 left join public.community_profiles n on n.user_id=case when t.payer_user_id=auth.uid() then t.payee_user_id else t.payer_user_id end
 where auth.uid() is not null and auth.uid() in (t.payer_user_id,t.payee_user_id) order by t.created_at desc limit 200;
$$;

create or replace function public.quest_transfer_details(p_transaction_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t private.quest_transactions%rowtype; d private.quest_transfer_details%rowtype;
begin
 select * into t from private.quest_transactions where id=p_transaction_id;
 if auth.uid() is null or not coalesce(auth.uid() in (t.payer_user_id,t.payee_user_id),false) then raise exception '거래 당사자만 조회할 수 있습니다'; end if;
 select * into d from private.quest_transfer_details where transaction_id=t.id and (delete_after is null or delete_after>now());
 if not found then return null; end if;
 return jsonb_build_object('bank_name',d.bank_name,'holder_name',d.holder_name,'account_number',d.account_number);
end $$;

create or replace function public.quest_save_transfer_details(p_transaction_id uuid,p_bank text,p_holder text,p_account text,p_version text,p_agreed boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(true); t private.quest_transactions%rowtype;
begin
 select * into t from private.quest_transactions where id=p_transaction_id for update;
 if t.payee_user_id is distinct from auth.uid() or t.status<>'awaiting_transfer' then raise exception '보상을 받을 당사자만 계좌를 등록할 수 있습니다'; end if;
 if p_agreed is distinct from true then raise exception '이 거래 상대방에게 계좌 정보를 제공하는 데 동의해 주세요'; end if;
 perform public.account_accept_policies(jsonb_build_object('transfer_disclosure',p_version),'transfer');
 insert into private.quest_transfer_details(transaction_id,bank_name,holder_name,account_number)
 values(t.id,btrim(p_bank),btrim(p_holder),regexp_replace(p_account,'[- ]','','g'))
 on conflict(transaction_id) do update set bank_name=excluded.bank_name,holder_name=excluded.holder_name,account_number=excluded.account_number,shared_at=now();
 insert into private.quest_events(quest_id,actor_subject_id,event,note) values(t.quest_id,s,'transfer_details_shared','recipient=payer; policy='||p_version);
 return true;
end $$;

create or replace function public.quest_transfer_report(p_transaction_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(true); t private.quest_transactions%rowtype;
begin
 select * into t from private.quest_transactions where id=p_transaction_id for update;
 if t.payer_user_id is distinct from auth.uid() or t.status<>'awaiting_transfer' then raise exception '송금 당사자만 완료 사실을 기록할 수 있습니다'; end if;
 update private.quest_transactions set status='transfer_reported',reported_at=now() where id=t.id;
 update public.quests set status='transfer_reported',updated_at=now() where id=t.quest_id;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(t.quest_id,s,'transfer_reported'); return true;
end $$;

create or replace function public.quest_remove_transfer_details(p_transaction_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(); t private.quest_transactions%rowtype;
begin
 select * into t from private.quest_transactions where id=p_transaction_id for update;
 if t.payee_user_id is distinct from auth.uid() then raise exception '계좌 제공자만 철회할 수 있습니다'; end if;
 delete from private.quest_transfer_details where transaction_id=t.id;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(t.quest_id,s,'transfer_details_withdrawn');
 return true;
end $$;

create or replace function public.quest_transfer_confirm(p_transaction_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(true); t private.quest_transactions%rowtype;
begin
 select * into t from private.quest_transactions where id=p_transaction_id for update;
 if t.payee_user_id is distinct from auth.uid() or t.status<>'transfer_reported' then raise exception '보상을 받는 당사자만 입금을 확인할 수 있습니다'; end if;
 update private.quest_transactions set status='received',received_at=now(),retain_until=now()+interval '5 years' where id=t.id;
 update private.quest_transfer_details set delete_after=now()+interval '30 days' where transaction_id=t.id;
 update public.quests set status='completed',updated_at=now() where id=t.quest_id;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(t.quest_id,s,'receipt_confirmed'); return true;
end $$;

create or replace function public.quest_dispute(p_transaction_id uuid,p_reason text) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(); t private.quest_transactions%rowtype;
begin
 select * into t from private.quest_transactions where id=p_transaction_id for update;
 if not coalesce(auth.uid() in (t.payer_user_id,t.payee_user_id),false) or t.status not in ('awaiting_transfer','transfer_reported') then raise exception '이 거래에 이의를 제기할 수 없습니다'; end if;
 if char_length(btrim(p_reason)) not between 10 and 1000 then raise exception '사유를 10~1000자로 적어주세요'; end if;
 update private.quest_transactions set status='disputed' where id=t.id;
 update public.quests set status='disputed',updated_at=now() where id=t.quest_id;
 insert into private.quest_events(quest_id,actor_subject_id,event,note) values(t.quest_id,s,'disputed',btrim(p_reason)); return true;
end $$;

create or replace function public.quest_cancel(p_quest_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare s uuid:=private.account_require_ready(); q public.quests%rowtype;
begin
 select * into q from public.quests where id=p_quest_id for update;
 if q.requester_user_id is distinct from auth.uid() or q.status<>'open' or exists(select 1 from public.quest_participations where quest_id=q.id and status in ('accepted','submitted','approved')) then
  raise exception '진행 중인 의뢰는 상대방과 협의 후 운영자에게 문의해 주세요'; end if;
 update public.quests set status='cancelled',updated_at=now() where id=q.id;
 insert into private.quest_events(quest_id,actor_subject_id,event) values(q.id,s,'cancelled'); return true;
end $$;

-- The guard also protects the legacy community_delete_account RPC and dashboard deletes.
create or replace function private.account_before_delete() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from private.quest_transactions where old.id in (payer_user_id,payee_user_id) and status<>'received') or
 exists(select 1 from public.quests q where q.status in ('assigned','awaiting_transfer','transfer_reported','disputed') and
 (q.requester_user_id=old.id or exists(select 1 from public.quest_participations p where p.quest_id=q.id and p.performer_user_id=old.id))) or
 exists(select 1 from public.quest_participations p join public.quests q on q.id=p.quest_id where q.status='open' and p.status='submitted' and (p.performer_user_id=old.id or q.requester_user_id=old.id)) then
  raise exception '진행 중인 퀘스트·미확인 송금·분쟁을 먼저 정리해 주세요. 삭제 지원: info@chargajoe.org'; end if;
 update public.quests set status='cancelled',updated_at=now() where requester_user_id=old.id and status='open';
 update private.account_subjects set closed_at=now() where user_id=old.id;
 delete from private.quest_transfer_details d using private.quest_transactions t where d.transaction_id=t.id and t.payee_user_id=old.id;
 return old;
end $$;
do $$ begin
 if not exists(select 1 from pg_trigger where tgname='account_preserve_transactions') then
  create trigger account_preserve_transactions before delete on auth.users for each row execute function private.account_before_delete();
 end if;
end $$;

create or replace function public.account_delete(p_confirm text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform private.account_subject();
 if p_confirm is distinct from '찾아줘 계정 삭제' then raise exception '확인 문구가 일치하지 않습니다'; end if;
 delete from auth.users where id=auth.uid(); return true;
end $$;

-- Run daily (cron job installed separately after verifying pg_cron availability).
create or replace function private.account_purge_expired() returns void
language plpgsql security definer set search_path='' as $$
begin
 delete from private.quest_transfer_details where delete_after<=now();
 update public.quest_participations p set result_text=null from private.quest_transactions t
 where p.quest_id=t.quest_id and t.status='received' and t.received_at<=now()-interval '30 days';
 delete from private.quest_events e using public.quests q where e.quest_id=q.id and q.status='cancelled' and q.updated_at<=now()-interval '30 days'
 and not exists(select 1 from private.quest_transactions t where t.quest_id=q.id);
 delete from public.quest_participations p using public.quests q where p.quest_id=q.id and q.status='cancelled' and q.updated_at<=now()-interval '30 days'
 and not exists(select 1 from private.quest_transactions t where t.quest_id=q.id);
 delete from public.quests q where q.status='cancelled' and q.updated_at<=now()-interval '30 days'
 and not exists(select 1 from private.quest_transactions t where t.quest_id=q.id);
 -- Only final, undisputed records expire; no cascade erases a live obligation.
 delete from private.quest_events e using private.quest_transactions t where e.quest_id=t.quest_id and t.status='received' and t.retain_until<=now();
 delete from private.quest_transfer_details d using private.quest_transactions t where d.transaction_id=t.id and t.status='received' and t.retain_until<=now();
 delete from private.quest_transactions where status='received' and retain_until<=now();
end $$;

-- Existing users get the same auth UUID; no email/nickname based identity matching.
insert into public.account_profiles(user_id) select id from auth.users on conflict(user_id) do nothing;
insert into private.account_subjects(user_id) select id from auth.users on conflict(user_id) do nothing;
create or replace function private.account_after_signup() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.account_profiles(user_id) values(new.id) on conflict(user_id) do nothing;
 insert into private.account_subjects(user_id) values(new.id) on conflict(user_id) do nothing;
 return new;
end $$;
do $$ begin
 if not exists(select 1 from pg_trigger where tgname='account_shared_identity') then
  create trigger account_shared_identity after insert on auth.users for each row execute function private.account_after_signup();
 end if;
end $$;

-- No blanket grants on existing functions or tables.
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (p.proname like 'account_%' or p.proname like 'quest_%') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to authenticated',f.signature);
  if f.proname in ('account_policies','quest_feed') then execute format('grant execute on function %s to anon',f.signature); end if;
 end loop;
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'account_%') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
