-- 찾아줘: lost-and-found MVP. Run once in Supabase SQL Editor AFTER community migration.
-- Only two SNU office locations are seeded; their coordinates reference SNU campus map.
-- Re-runnable: CREATE IF NOT EXISTS, CREATE OR REPLACE functions, UPSERT centers.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.lf_centers (
 id text PRIMARY KEY, name text NOT NULL, building text NOT NULL, room text NOT NULL,
 latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
 longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
 phone text, weekday_hours text, weekend_holiday_note text NOT NULL,
 custody_note text NOT NULL, source_url text NOT NULL, checked_on date NOT NULL,
 active boolean NOT NULL DEFAULT true
);
CREATE TABLE IF NOT EXISTS public.lf_found_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 category text NOT NULL CHECK (category IN ('지갑','전자기기','학생증','우산','의류','가방','열쇠','기타')),
 title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 100),
 description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 1000),
 location_name text NOT NULL CHECK (char_length(location_name) BETWEEN 2 AND 120),
 latitude double precision NOT NULL CHECK (latitude BETWEEN 33 AND 39),
 longitude double precision NOT NULL CHECK (longitude BETWEEN 124 AND 132),
 found_at timestamptz NOT NULL,
 custody text NOT NULL CHECK (custody IN ('finder','center','sighting')),
 center_id text REFERENCES public.lf_centers(id),
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','handed_over','returned','closed')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT lf_found_center_required CHECK (custody <> 'center' OR center_id IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS public.lf_lost_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 category text NOT NULL CHECK (category IN ('지갑','전자기기','학생증','우산','의류','가방','열쇠','기타')),
 title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 100),
 description text NOT NULL CHECK (char_length(description) BETWEEN 2 AND 1000),
 location_name text NOT NULL CHECK (char_length(location_name) BETWEEN 2 AND 120),
 latitude double precision NOT NULL CHECK (latitude BETWEEN 33 AND 39),
 longitude double precision NOT NULL CHECK (longitude BETWEEN 124 AND 132),
 lost_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','resolved','closed')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.lf_claims (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), found_id uuid NOT NULL REFERENCES public.lf_found_items(id) ON DELETE CASCADE,
 claimant_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 proof_note text NOT NULL CHECK (char_length(proof_note) BETWEEN 10 AND 500),
 status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (found_id,claimant_id)
);
CREATE TABLE IF NOT EXISTS public.lf_leads (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL REFERENCES public.lf_lost_requests(id) ON DELETE CASCADE,
 found_id uuid NOT NULL REFERENCES public.lf_found_items(id) ON DELETE CASCADE,
 reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(request_id,found_id)
);
CREATE INDEX IF NOT EXISTS lf_found_active_idx ON public.lf_found_items(status,created_at DESC);
CREATE INDEX IF NOT EXISTS lf_lost_active_idx ON public.lf_lost_requests(status,created_at DESC);
CREATE INDEX IF NOT EXISTS lf_claim_inbox_idx ON public.lf_claims(found_id,created_at DESC);
CREATE INDEX IF NOT EXISTS lf_leads_request_idx ON public.lf_leads(request_id);

-- Official SNU notices: https://sees.snu.ac.kr/community/notice?bbsidx=17914&md=v
-- SNU Student Affairs notice 2025-01-03: https://teststudent.snu.ac.kr/...uid=153
-- For 67, office hours and exact holiday opening were NOT published: do not infer.
INSERT INTO public.lf_centers
(id,name,building,room,latitude,longitude,phone,weekday_hours,weekend_holiday_note,custody_note,source_url,checked_on)
VALUES
('snu101','서울대학교 분실물센터','101동 아시아연구소','1층 캠퍼스안전반',37.46328,126.95015,'02-880-8114','평일 09:00~18:00',
 '토·일요일 및 공휴일 분실물 접수·수령 운영은 사전 전화 확인',
 '공식 분실물센터. 캠퍼스안전반 당직(02-880-8112 / 8119)은 24시간 운영하지만 분실물센터 수령 시간과 다릅니다.',
 'https://sees.snu.ac.kr/community/notice?bbsidx=17914&md=v','2026-10-28'),
('snu67','두레문예관 학생지원센터 임시 보관처','67동 두레문예관','201호 학생지원센터',37.46353,126.94973,NULL,NULL,
 '운영시간·휴무일 공식 확인 불가: 방문 전 담당 부서에 확인',
 '67동 내 습득물만 2영업일 임시 보관하고 101동 분실물센터로 이관. 별도의 중앙 분실물센터가 아닙니다.',
 'https://student.snu.ac.kr/%EC%86%8C%EC%8B%9D%C2%B7%EC%95%8C%EB%A6%BC/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/?mod=document&pageid=10&uid=153','2026-10-28')
ON CONFLICT (id) DO UPDATE SET name=excluded.name,building=excluded.building,room=excluded.room,
 latitude=excluded.latitude,longitude=excluded.longitude,phone=excluded.phone,
 weekday_hours=excluded.weekday_hours,weekend_holiday_note=excluded.weekend_holiday_note,
 custody_note=excluded.custody_note,source_url=excluded.source_url,checked_on=excluded.checked_on;

-- Deny direct table access. ONLY whitelisted SECURITY DEFINER functions expose fields.
ALTER TABLE public.lf_centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_found_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_lost_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_leads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lf_centers, public.lf_found_items, public.lf_lost_requests, public.lf_claims, public.lf_leads FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.lf_centers_list() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(c) - 'active' ORDER BY c.id),'[]'::jsonb) FROM public.lf_centers c WHERE c.active;
$$;

CREATE OR REPLACE FUNCTION public.lf_found_list() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'id',f.id,'category',f.category,'title',f.title,'description',f.description,
 'location_name',f.location_name,'latitude',f.latitude,'longitude',f.longitude,
 'event_at',f.found_at,'custody',f.custody,'center_id',f.center_id,
 'status',f.status,'created_at',f.created_at,
 'mine',f.author_id=auth.uid()) ORDER BY f.created_at DESC),'[]'::jsonb)
 FROM (SELECT * FROM public.lf_found_items WHERE status IN ('active','handed_over') ORDER BY created_at DESC LIMIT 200) f;
$$;

CREATE OR REPLACE FUNCTION public.lf_lost_list() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'id',l.id,'category',l.category,'title',l.title,'description',l.description,
 'location_name',l.location_name,'latitude',l.latitude,'longitude',l.longitude,
 'event_at',l.lost_at,'status',l.status,'created_at',l.created_at,
 'mine',l.author_id=auth.uid()) ORDER BY l.created_at DESC),'[]'::jsonb)
 FROM (SELECT * FROM public.lf_lost_requests WHERE status='active' ORDER BY created_at DESC LIMIT 200) l;
$$;

CREATE OR REPLACE FUNCTION public.lf_found_create(
 p_category text,p_title text,p_description text,p_location_name text,p_latitude double precision,
 p_longitude double precision,p_event_at timestamptz,p_custody text,p_center_id text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다'; END IF;
 IF p_event_at IS NULL OR p_event_at > now()+interval '5 minutes' THEN RAISE EXCEPTION '습득 시간이 올바르지 않습니다'; END IF;
 IF p_custody = 'center' AND NOT EXISTS(SELECT 1 FROM public.lf_centers WHERE id=p_center_id AND active) THEN RAISE EXCEPTION '보관처를 선택해 주세요'; END IF;
 INSERT INTO public.lf_found_items(author_id,category,title,description,location_name,latitude,longitude,found_at,custody,center_id)
 VALUES(auth.uid(),p_category,trim(p_title),coalesce(trim(p_description),''),trim(p_location_name),p_latitude,p_longitude,p_event_at,p_custody,
 CASE WHEN p_custody='center' THEN p_center_id ELSE NULL END) RETURNING id INTO v_id;
 RETURN v_id;
END;$$;
CREATE OR REPLACE FUNCTION public.lf_lost_create(
 p_category text,p_title text,p_description text,p_location_name text,p_latitude double precision,
 p_longitude double precision,p_event_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다'; END IF;
 IF p_event_at IS NULL OR p_event_at > now()+interval '5 minutes' THEN RAISE EXCEPTION '분실 시간이 올바르지 않습니다'; END IF;
 INSERT INTO public.lf_lost_requests(author_id,category,title,description,location_name,latitude,longitude,lost_at)
 VALUES(auth.uid(),p_category,trim(p_title),trim(p_description),trim(p_location_name),p_latitude,p_longitude,p_event_at)
 RETURNING id INTO v_id;
 RETURN v_id;
END;$$;
CREATE OR REPLACE FUNCTION public.lf_found_status(p_id uuid,p_status text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
BEGIN
 IF p_status NOT IN ('handed_over','returned','closed') THEN RAISE EXCEPTION '허용되지 않는 상태입니다'; END IF;
 UPDATE public.lf_found_items SET status=p_status,updated_at=now() WHERE id=p_id AND author_id=auth.uid();
 RETURN FOUND;
END;$$;
CREATE OR REPLACE FUNCTION public.lf_lost_status(p_id uuid,p_status text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
BEGIN
 IF p_status NOT IN ('resolved','closed') THEN RAISE EXCEPTION '허용되지 않는 상태입니다'; END IF;
 UPDATE public.lf_lost_requests SET status=p_status,updated_at=now() WHERE id=p_id AND author_id=auth.uid();
 RETURN FOUND;
END;$$;
CREATE OR REPLACE FUNCTION public.lf_claim_create(p_found_id uuid,p_proof_note text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_found_items WHERE id=p_found_id AND status IN ('active','handed_over') AND author_id<>auth.uid()) THEN
  RAISE EXCEPTION '요청할 수 없는 습득물입니다'; END IF;
 INSERT INTO public.lf_claims(found_id,claimant_id,proof_note) VALUES(p_found_id,auth.uid(),trim(p_proof_note)) ON CONFLICT (found_id,claimant_id) DO NOTHING;
 RETURN TRUE;
END;$$;
CREATE OR REPLACE FUNCTION public.lf_my_claims_inbox() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'found_id',c.found_id,'found_title',f.title,
 'proof_note',c.proof_note,'status',c.status,'created_at',c.created_at) ORDER BY c.created_at DESC),'[]'::jsonb)
 FROM public.lf_claims c JOIN public.lf_found_items f ON f.id=c.found_id
 WHERE f.author_id=auth.uid();
$$;
-- A claimant can review their own request status without reading another user's claims.
CREATE OR REPLACE FUNCTION public.lf_my_claims() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'found_id',c.found_id,'found_title',f.title,
 'proof_note',c.proof_note,'status',c.status,'created_at',c.created_at) ORDER BY c.created_at DESC),'[]'::jsonb)
 FROM public.lf_claims c JOIN public.lf_found_items f ON f.id=c.found_id
 WHERE c.claimant_id=auth.uid();
$$;
CREATE OR REPLACE FUNCTION public.lf_claim_resolve(p_claim_id uuid,p_status text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
BEGIN
 IF p_status NOT IN ('accepted','rejected') THEN RAISE EXCEPTION '허용되지 않는 상태입니다'; END IF;
 UPDATE public.lf_claims c SET status=p_status FROM public.lf_found_items f
 WHERE c.id=p_claim_id AND f.id=c.found_id AND f.author_id=auth.uid() AND c.status='pending';
 RETURN FOUND;
END;$$;
CREATE OR REPLACE FUNCTION public.lf_lead_create(p_request_id uuid,p_found_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_lost_requests WHERE id=p_request_id AND status='active')
    OR NOT EXISTS(SELECT 1 FROM public.lf_found_items WHERE id=p_found_id AND status IN ('active','handed_over') AND author_id=auth.uid())
 THEN RAISE EXCEPTION '연결할 수 없는 분실 의뢰 또는 습득물입니다'; END IF;
 INSERT INTO public.lf_leads(request_id,found_id,reporter_id) VALUES(p_request_id,p_found_id,auth.uid()) ON CONFLICT(request_id,found_id) DO NOTHING;
 RETURN TRUE;
END;$$;
CREATE OR REPLACE FUNCTION public.lf_my_leads() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('request_id',l.request_id,'found_id',l.found_id,'found_title',f.title,
 'created_at',l.created_at) ORDER BY l.created_at DESC),'[]'::jsonb)
 FROM public.lf_leads l JOIN public.lf_lost_requests r ON r.id=l.request_id
 JOIN public.lf_found_items f ON f.id=l.found_id WHERE r.author_id=auth.uid();
$$;

REVOKE ALL ON FUNCTION public.lf_centers_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_found_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_lost_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_found_create(text,text,text,text,double precision,double precision,timestamptz,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_lost_create(text,text,text,text,double precision,double precision,timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_found_status(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_lost_status(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_claim_create(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_my_claims_inbox() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_my_claims() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_claim_resolve(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_lead_create(uuid,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lf_my_leads() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.lf_centers_list() TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_found_list(),public.lf_lost_list(),
 public.lf_found_create(text,text,text,text,double precision,double precision,timestamptz,text,text),
 public.lf_lost_create(text,text,text,text,double precision,double precision,timestamptz),
 public.lf_found_status(uuid,text),public.lf_lost_status(uuid,text),
 public.lf_claim_create(uuid,text),public.lf_my_claims_inbox(),public.lf_my_claims(),public.lf_claim_resolve(uuid,text),
 public.lf_lead_create(uuid,uuid),public.lf_my_leads() TO authenticated;
