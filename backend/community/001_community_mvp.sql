-- 찾아줘 사랑방 MVP — Supabase PostgreSQL, run once in SQL Editor.
-- Design: all member-facing tables are private; the app only calls SECURITY DEFINER RPCs.
-- Never expose author_id of anonymous content through a client-readable view/table.
create extension if not exists pgcrypto;

create table if not exists public.community_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  role text not null default 'member' check (role in ('member','moderator')),
  created_at timestamptz not null default now(),
  constraint community_nickname_format check (nickname ~ '^[가-힣A-Za-z0-9_]{2,20}$')
);
create unique index if not exists community_nickname_unique on public.community_profiles(lower(nickname));

create table if not exists public.community_posts (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references auth.users(id) on delete cascade,
 board text not null check (board in ('free','question','goodwill')),
 title text not null check (char_length(btrim(title)) between 2 and 120),
 body text not null check (char_length(btrim(body)) between 2 and 10000),
 display_mode text not null check (display_mode in ('anonymous','nickname')),
 tags text[] not null default '{}',
 info_kind text check (info_kind in ('experience','study','official','practical')),
 source_url text,
 expires_at date,
 review_state text not null default 'unreviewed'
   check (review_state in ('unreviewed','pending','source_checked','recommended','rejected')),
 hidden boolean not null default false,
 deleted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint community_source_url_https check (source_url is null or source_url ~ '^https://[^[:space:]]+$'),
 constraint community_info_only check (board = 'goodwill' or (info_kind is null and source_url is null and expires_at is null))
);
create index if not exists community_posts_feed on public.community_posts(board, created_at desc) where hidden = false and deleted_at is null;
create index if not exists community_posts_author on public.community_posts(author_id, created_at desc);

create table if not exists public.community_comments (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.community_posts(id) on delete cascade,
 author_id uuid not null references auth.users(id) on delete cascade,
 body text not null check (char_length(btrim(body)) between 1 and 2000),
 display_mode text not null check (display_mode in ('anonymous','nickname')),
 hidden boolean not null default false,
 deleted_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists community_comments_post on public.community_comments(post_id,created_at);

create table if not exists public.community_saves (
 user_id uuid not null references auth.users(id) on delete cascade,
 post_id uuid not null references public.community_posts(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (user_id,post_id)
);
create table if not exists public.community_reactions (
 user_id uuid not null references auth.users(id) on delete cascade,
 post_id uuid not null references public.community_posts(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (user_id,post_id)
);
create table if not exists public.community_blocks (
 id uuid unique not null default gen_random_uuid(),
 blocker_id uuid not null references auth.users(id) on delete cascade,
 blocked_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (blocker_id,blocked_id),
 check (blocker_id <> blocked_id)
);
create table if not exists public.community_reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references auth.users(id) on delete cascade,
 post_id uuid references public.community_posts(id) on delete cascade,
 comment_id uuid references public.community_comments(id) on delete cascade,
 reason text not null check (char_length(btrim(reason)) between 2 and 500),
 state text not null default 'pending' check (state in ('pending','resolved','dismissed')),
 created_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 check (num_nonnulls(post_id,comment_id) = 1)
);
create unique index if not exists community_report_unique_post on public.community_reports(reporter_id,post_id) where post_id is not null;
create unique index if not exists community_report_unique_comment on public.community_reports(reporter_id,comment_id) where comment_id is not null;

create table if not exists public.community_reviews (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.community_posts(id) on delete cascade,
 reviewer_id uuid references auth.users(id) on delete set null,
 state text not null check (state in ('source_checked','recommended','rejected')),
 note text not null default '',
 created_at timestamptz not null default now()
);
create table if not exists public.community_contributions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 post_id uuid not null references public.community_posts(id) on delete cascade,
 kind text not null default 'approved_information',
 recorded_at timestamptz not null default now(),
 unique(user_id,post_id,kind)
);

-- No direct table access, including profiles and the anonymous-to-user mapping.
do $$
declare t text;
begin
 foreach t in array array['community_profiles','community_posts','community_comments','community_saves','community_reactions',
  'community_blocks','community_reports','community_reviews','community_contributions'] loop
  execute format('alter table public.%I enable row level security', t);
  execute format('revoke all on table public.%I from public, anon, authenticated', t);
 end loop;
end $$;

create or replace function public.community_ensure_profile() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); p public.community_profiles%rowtype;
begin
 if u is null then raise exception 'Login required' using errcode='28000'; end if;
 insert into public.community_profiles(user_id,nickname) values
 (u, '학생_' || substr(replace(u::text,'-',''),1,10)) on conflict(user_id) do nothing;
 select * into p from public.community_profiles where user_id=u;
 return jsonb_build_object('nickname',p.nickname,'role',p.role);
end; $$;

create or replace function public.community_set_nickname(p_nickname text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); n text := btrim(p_nickname);
begin
 if u is null then raise exception 'Login required' using errcode='28000'; end if;
 if n !~ '^[가-힣A-Za-z0-9_]{2,20}$' then raise exception 'Nickname must be 2-20 letters, numbers, underscores' using errcode='22023'; end if;
 perform public.community_ensure_profile();
 update public.community_profiles set nickname=n where user_id=u;
 return public.community_ensure_profile();
end; $$;

create or replace function public.community_is_moderator() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.community_profiles where user_id=auth.uid() and role='moderator');
$$;

-- Returns a sanitized object, intentionally omitting author_id and profile identifiers.
create or replace function public.community_post_view(p_post_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
 select jsonb_build_object(
 'id',p.id,'board',p.board,'title',p.title,'body',p.body,'display_mode',p.display_mode,
 'author_display',case when p.display_mode='anonymous' then '익명' else coalesce(pr.nickname,'회원') end,
 'created_at',p.created_at,'updated_at',p.updated_at,'tags',p.tags,
 'info_kind',p.info_kind,'source_url',p.source_url,'expires_at',p.expires_at,
 'review_state',p.review_state,'mine',p.author_id=auth.uid(),
 'is_saved',exists(select 1 from public.community_saves s where s.post_id=p.id and s.user_id=auth.uid()),
 'is_liked',exists(select 1 from public.community_reactions r where r.post_id=p.id and r.user_id=auth.uid()),
 'save_count',(select count(*) from public.community_saves s where s.post_id=p.id),
 'like_count',(select count(*) from public.community_reactions r where r.post_id=p.id),
 'comment_count',(select count(*) from public.community_comments c where c.post_id=p.id and c.deleted_at is null and not c.hidden)
 )
 from public.community_posts p
 left join public.community_profiles pr on pr.user_id=p.author_id
 where auth.uid() is not null and p.id=p_post_id and not p.hidden and p.deleted_at is null
 and not exists(select 1 from public.community_blocks b where b.blocker_id=auth.uid() and b.blocked_id=p.author_id);
$$;

create or replace function public.community_feed(
 p_board text default null, p_query text default null, p_tag text default null,
 p_saved_only boolean default false, p_limit integer default 30, p_offset integer default 0)
returns setof jsonb language sql stable security definer set search_path = '' as $$
 select public.community_post_view(p.id)
 from public.community_posts p
 where auth.uid() is not null and not p.hidden and p.deleted_at is null
 and (p_board is null or p.board=p_board)
 and (p_tag is null or p_tag=any(p.tags))
 and (p_query is null or p.title ilike '%' || left(p_query,100) || '%' or p.body ilike '%' || left(p_query,100) || '%')
 and (not p_saved_only or exists(select 1 from public.community_saves s where s.user_id=auth.uid() and s.post_id=p.id))
 and not exists(select 1 from public.community_blocks b where b.blocker_id=auth.uid() and b.blocked_id=p.author_id)
 order by p.created_at desc, p.id desc
 limit least(greatest(coalesce(p_limit,30),1),60) offset least(greatest(coalesce(p_offset,0),0),10000);
$$;

create or replace function public.community_create_post(
 p_board text,p_title text,p_body text,p_display_mode text,p_tags text[] default '{}',
 p_info_kind text default null,p_source_url text default null,p_expires_at date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); new_id uuid; clean_tags text[] := coalesce(p_tags,'{}');
begin
 if u is null then raise exception 'Login required' using errcode='28000'; end if;
 if p_board not in ('free','question','goodwill') or p_display_mode not in ('anonymous','nickname')
 or char_length(btrim(p_title)) not between 2 and 120 or char_length(btrim(p_body)) not between 2 and 10000 then
 raise exception 'Invalid post fields' using errcode='22023'; end if;
 if cardinality(clean_tags)>5 or exists(select 1 from unnest(clean_tags) t where length(t)>30 or length(t)<1)
 then raise exception 'Invalid tags' using errcode='22023'; end if;
 if (select count(*) from public.community_posts where author_id=u and created_at>now()-interval '10 minutes') >= 5 then
 raise exception 'Too many posts, try again later' using errcode='22023'; end if;
 if p_board <> 'goodwill' and (p_info_kind is not null or p_source_url is not null or p_expires_at is not null) then
 raise exception 'Information metadata only for goodwill' using errcode='22023'; end if;
 perform public.community_ensure_profile();
 insert into public.community_posts(author_id,board,title,body,display_mode,tags,info_kind,source_url,expires_at,
 review_state) values(u,p_board,btrim(p_title),btrim(p_body),p_display_mode,clean_tags,p_info_kind,
 nullif(btrim(coalesce(p_source_url,'')),''),p_expires_at,
 case when p_board='goodwill' then 'pending' else 'unreviewed' end)
 returning id into new_id;
 return public.community_post_view(new_id);
end; $$;

create or replace function public.community_delete_post(p_post_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='28000'; end if;
 update public.community_posts set deleted_at=now(),updated_at=now() where id=p_post_id and author_id=auth.uid() and deleted_at is null;
 return found;
end; $$;

create or replace function public.community_comments_list(p_post_id uuid)
returns setof jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('id',c.id,'post_id',c.post_id,'body',c.body,
 'author_display',case when c.display_mode='anonymous' then '익명' else coalesce(pr.nickname,'회원') end,
 'display_mode',c.display_mode,'mine',c.author_id=auth.uid(),'created_at',c.created_at)
 from public.community_comments c
 join public.community_posts p on p.id=c.post_id
 left join public.community_profiles pr on pr.user_id=c.author_id
 where auth.uid() is not null and p.id=p_post_id and not p.hidden and p.deleted_at is null
 and not c.hidden and c.deleted_at is null
 and not exists(select 1 from public.community_blocks b where b.blocker_id=auth.uid() and b.blocked_id=p.author_id)
 and not exists(select 1 from public.community_blocks b where b.blocker_id=auth.uid() and b.blocked_id=c.author_id)
 order by c.created_at asc limit 500;
$$;

create or replace function public.community_create_comment(p_post_id uuid,p_body text,p_display_mode text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='28000'; end if;
 if p_display_mode not in ('anonymous','nickname') or char_length(btrim(p_body)) not between 1 and 2000 then
 raise exception 'Invalid comment' using errcode='22023'; end if;
 if not exists(select 1 from public.community_posts p where id=p_post_id and not p.hidden and p.deleted_at is null) then
 raise exception 'Post unavailable' using errcode='22023'; end if;
 if (select count(*) from public.community_comments where author_id=auth.uid() and created_at>now()-interval '10 minutes') >= 20 then
 raise exception 'Too many comments, try again later' using errcode='22023'; end if;
 insert into public.community_comments(post_id,author_id,body,display_mode) values(p_post_id,auth.uid(),btrim(p_body),p_display_mode);
 return true;
end; $$;

create or replace function public.community_delete_comment(p_comment_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='28000'; end if;
 update public.community_comments set deleted_at=now() where id=p_comment_id and author_id=auth.uid() and deleted_at is null;
 return found;
end; $$;

create or replace function public.community_toggle_save(p_post_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
 if public.community_post_view(p_post_id) is null then raise exception 'Post unavailable' using errcode='22023'; end if;
 delete from public.community_saves where user_id=auth.uid() and post_id=p_post_id;
 if found then return false; end if;
 insert into public.community_saves(user_id,post_id) values(auth.uid(),p_post_id);
 return true;
end; $$;

create or replace function public.community_toggle_like(p_post_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
 if public.community_post_view(p_post_id) is null then raise exception 'Post unavailable' using errcode='22023'; end if;
 delete from public.community_reactions where user_id=auth.uid() and post_id=p_post_id;
 if found then return false; end if;
 insert into public.community_reactions(user_id,post_id) values(auth.uid(),p_post_id);
 return true;
end; $$;

create or replace function public.community_report(p_post_id uuid,p_comment_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='28000'; end if;
 if num_nonnulls(p_post_id,p_comment_id)<>1 or char_length(btrim(p_reason)) not between 2 and 500 then
 raise exception 'Invalid report' using errcode='22023'; end if;
 if p_post_id is not null and public.community_post_view(p_post_id) is null then
 raise exception 'Post unavailable' using errcode='22023'; end if;
 if p_comment_id is not null and not exists (
  select 1 from public.community_comments c join public.community_posts p on p.id=c.post_id
  where c.id=p_comment_id and not c.hidden and c.deleted_at is null and not p.hidden and p.deleted_at is null)
 then raise exception 'Comment unavailable' using errcode='22023'; end if;
 if (select count(*) from public.community_reports where reporter_id=auth.uid() and created_at>now()-interval '1 day') >= 20 then
 raise exception 'Daily report limit reached' using errcode='22023'; end if;
 insert into public.community_reports(reporter_id,post_id,comment_id,reason)
 values(auth.uid(),p_post_id,p_comment_id,btrim(p_reason)) on conflict do nothing;
 return true;
end; $$;

create or replace function public.community_block_author(p_post_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='28000'; end if;
 select author_id into target from public.community_posts where id=p_post_id and not hidden and deleted_at is null;
 if target is null or target=auth.uid() then raise exception 'Cannot block this author' using errcode='22023'; end if;
 insert into public.community_blocks(blocker_id,blocked_id) values(auth.uid(),target) on conflict do nothing;
 return true;
end; $$;

create or replace function public.community_admin_pending()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
 if not public.community_is_moderator() then raise exception 'Moderator only' using errcode='42501'; end if;
 return query select public.community_post_view(p.id)
 from public.community_posts p where p.board='goodwill' and p.review_state='pending'
 and not p.hidden and p.deleted_at is null order by p.created_at limit 100;
end; $$;

create or replace function public.community_admin_review(p_post_id uuid,p_state text,p_note text default '')
returns boolean language plpgsql security definer set search_path = '' as $$
declare a uuid;
begin
 if not public.community_is_moderator() then raise exception 'Moderator only' using errcode='42501'; end if;
 if p_state not in ('source_checked','recommended','rejected') or length(coalesce(p_note,''))>1000 then
 raise exception 'Invalid review' using errcode='22023'; end if;
 update public.community_posts set review_state=p_state,updated_at=now()
 where id=p_post_id and board='goodwill' and deleted_at is null and not hidden
 returning author_id into a;
 if a is null then return false; end if;
 insert into public.community_reviews(post_id,reviewer_id,state,note)
 values(p_post_id,auth.uid(),p_state,coalesce(p_note,''));
 if p_state in ('source_checked','recommended') then
  insert into public.community_contributions(user_id,post_id,kind)
  values(a,p_post_id,'approved_information') on conflict do nothing;
 end if;
 return true;
end; $$;

create or replace function public.community_my_contributions()
returns setof jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('post_id',c.post_id,'kind',c.kind,'recorded_at',c.recorded_at,'title',p.title)
 from public.community_contributions c join public.community_posts p on p.id=c.post_id
 where auth.uid() is not null and c.user_id=auth.uid() order by c.recorded_at desc limit 100;
$$;

create or replace function public.community_admin_reports()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
begin
 if not public.community_is_moderator() then raise exception 'Moderator only' using errcode='42501'; end if;
 return query select jsonb_build_object('id',r.id,'post_id',r.post_id,'comment_id',r.comment_id,
 'reason',r.reason,'created_at',r.created_at)
 from public.community_reports r where r.state='pending' order by r.created_at limit 100;
end; $$;

create or replace function public.community_admin_resolve_report(p_report_id uuid,p_hide boolean,p_dismiss boolean default false)
returns boolean language plpgsql security definer set search_path = '' as $$
declare r public.community_reports%rowtype;
begin
 if not public.community_is_moderator() then raise exception 'Moderator only' using errcode='42501'; end if;
 select * into r from public.community_reports where id=p_report_id and state='pending' for update;
 if not found then return false; end if;
 if p_hide then
   if r.post_id is not null then update public.community_posts set hidden=true where id=r.post_id; end if;
   if r.comment_id is not null then update public.community_comments set hidden=true where id=r.comment_id; end if;
 end if;
 update public.community_reports set state=case when p_dismiss then 'dismissed' else 'resolved' end,
 reviewed_by=auth.uid(),reviewed_at=now() where id=p_report_id;
 return true;
end; $$;

-- Self-service account deletion. Only the JWT owner can delete their *own* auth account.
-- The auth.users cascades erase their posts, comments, saves and contribution history.
-- Opaque block handle: never expose blocked_id (may unmask an anonymous author).
create or replace function public.community_my_blocks()
returns setof jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('id',b.id,'created_at',b.created_at)
 from public.community_blocks b where auth.uid() is not null and b.blocker_id=auth.uid()
 order by b.created_at desc limit 200;
$$;

create or replace function public.community_unblock(p_block_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='28000'; end if;
 delete from public.community_blocks where id=p_block_id and blocker_id=auth.uid();
 return found;
end; $$;

create or replace function public.community_delete_account(p_confirm text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
 if u is null then raise exception 'Login required' using errcode='28000'; end if;
 if p_confirm <> '사랑방 계정 삭제' then raise exception 'Confirmation phrase mismatch' using errcode='22023'; end if;
 delete from auth.users where id=u;
 if not found then raise exception 'Account not found' using errcode='22023'; end if;
 return true;
end; $$;

-- Supabase default schema grants allow function execution to PUBLIC unless revoked.
-- Restrict *only our functions*, never revoke access to unrelated Supabase functions.
do $$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'community_%' loop
   execute format('revoke all on function %s from public, anon',f.signature);
   execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;

-- Explicitly assign the initial moderator from Supabase SQL Editor, after user registration:
-- UPDATE public.community_profiles SET role='moderator' WHERE user_id = '<authenticated-user-uuid>'::uuid;
-- Never allow role updates from a client API. Apply rate limits and content moderation before wider launch.
