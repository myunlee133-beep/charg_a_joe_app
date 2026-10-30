-- 찾아줘 unified found items. Apply after community/001 and lost_found/001.
-- This migration preserves legacy tables and rows. Deploy the unified iOS client
-- together with this migration: previous lost-request RPCs are intentionally revoked.
BEGIN;

CREATE TABLE IF NOT EXISTS public.lf_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 source text NOT NULL CHECK (source IN ('mysnu','staff','user')),
 source_id text,
 author_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 category text NOT NULL CHECK (category IN ('지갑','전자기기','학생증','우산','의류','가방','열쇠','기타')),
 title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 2 AND 100),
 description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 1000),
 location_name text NOT NULL CHECK (char_length(btrim(location_name)) BETWEEN 2 AND 120),
 latitude double precision NOT NULL CHECK (latitude BETWEEN 33 AND 39),
 longitude double precision NOT NULL CHECK (longitude BETWEEN 124 AND 132),
 registered_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'stored' CHECK (status IN ('stored','received','police')),
 photo_url text CHECK (photo_url IS NULL OR (char_length(photo_url) <= 2048 AND photo_url ~ '^https://[A-Za-z0-9][A-Za-z0-9.:-]+(/[^[:space:]@]*)?$')),
 photo_jpeg bytea CHECK (photo_jpeg IS NULL OR (octet_length(photo_jpeg) BETWEEN 4 AND 524288
    AND substring(photo_jpeg FROM 1 FOR 3) = decode('ffd8ff','hex')
    AND substring(photo_jpeg FROM octet_length(photo_jpeg)-1 FOR 2) = decode('ffd9','hex'))),
 received_reason text CHECK (received_reason IN ('claim_completed','source_removed','legacy_closed')),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK ((source = 'mysnu' AND source_id IS NOT NULL AND char_length(source_id) BETWEEN 1 AND 128)
     OR (source IN ('staff','user') AND source_id IS NULL)),
 CHECK (status = 'received' OR received_reason IS NULL),
 UNIQUE (source,source_id)
);
CREATE INDEX IF NOT EXISTS lf_items_visible ON public.lf_items(registered_at DESC,id) WHERE status <> 'received';
CREATE INDEX IF NOT EXISTS lf_items_author ON public.lf_items(author_id);

CREATE TABLE IF NOT EXISTS public.lf_item_claims (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 item_id uuid NOT NULL REFERENCES public.lf_items(id),
 claimant_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 proof text NOT NULL CHECK (char_length(btrim(proof)) BETWEEN 10 AND 500),
 status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','received','not_mine','not_received')),
 verified_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 verified_at timestamptz,
 completed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(item_id,claimant_id)
);
CREATE INDEX IF NOT EXISTS lf_item_claims_claimant ON public.lf_item_claims(claimant_id,created_at DESC);
CREATE INDEX IF NOT EXISTS lf_item_claims_item ON public.lf_item_claims(item_id,created_at DESC);

CREATE TABLE IF NOT EXISTS public.lf_item_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 item_id uuid NOT NULL REFERENCES public.lf_items(id),
 actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 kind text NOT NULL,
 detail jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.lf_sync_runs (
 run_id uuid PRIMARY KEY,
 fingerprint text NOT NULL,
 complete boolean NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);

-- Keep identifiers stable so archived claim references remain meaningful.
INSERT INTO public.lf_items(id,source,author_id,category,title,description,location_name,latitude,longitude,
                          registered_at,status,received_reason,created_at,updated_at)
SELECT f.id,CASE WHEN EXISTS(SELECT 1 FROM public.community_profiles p WHERE p.user_id=f.author_id AND p.role='moderator')
                THEN 'staff' ELSE 'user' END,
 f.author_id,f.category,f.title,f.description,f.location_name,f.latitude,f.longitude,f.created_at,
 CASE WHEN f.status IN ('returned','closed') THEN 'received' ELSE 'stored' END,
 CASE WHEN f.status IN ('returned','closed') THEN 'legacy_closed' ELSE NULL END,f.created_at,f.updated_at
FROM public.lf_found_items f ON CONFLICT(id) DO NOTHING;

INSERT INTO public.lf_item_claims(id,item_id,claimant_id,proof,status,created_at,updated_at)
SELECT c.id,c.found_id,c.claimant_id,c.proof_note,c.status,c.created_at,c.created_at
FROM public.lf_claims c JOIN public.lf_items i ON i.id=c.found_id
ON CONFLICT(id) DO NOTHING;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['lf_items','lf_item_claims','lf_item_events','lf_sync_runs',
   'lf_found_items','lf_lost_requests','lf_claims','lf_leads'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
END $$;
REVOKE ALL ON SEQUENCE public.lf_item_events_id_seq FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.lf_items_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',i.id,'source',i.source,'source_id',i.source_id,'category',i.category,'title',i.title,
  'description',i.description,'location_name',i.location_name,'latitude',i.latitude,'longitude',i.longitude,
  'registered_at',i.registered_at,'status',i.status,'photo_url',i.photo_url,'photo_base64',NULL,
  'mine',coalesce(i.author_id=auth.uid(),false)) ORDER BY i.registered_at DESC,i.id),'[]'::jsonb)
 FROM public.lf_items i WHERE i.status IN ('stored','police'));
END $$;

CREATE OR REPLACE FUNCTION public.lf_item_detail(p_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 RETURN (SELECT jsonb_build_object(
  'id',i.id,'source',i.source,'source_id',i.source_id,'category',i.category,'title',i.title,
  'description',i.description,'location_name',i.location_name,'latitude',i.latitude,'longitude',i.longitude,
  'registered_at',i.registered_at,'status',i.status,'photo_url',i.photo_url,
  'photo_base64',CASE WHEN i.photo_jpeg IS NULL THEN NULL ELSE replace(encode(i.photo_jpeg,'base64'),E'\n','') END,
  'mine',coalesce(i.author_id=auth.uid(),false))
 FROM public.lf_items i WHERE i.id=p_item_id AND
  (i.status <> 'received' OR i.author_id=auth.uid()
   OR EXISTS(SELECT 1 FROM public.lf_item_claims c WHERE c.item_id=i.id AND c.claimant_id=auth.uid())
   OR EXISTS(SELECT 1 FROM public.community_profiles p WHERE p.user_id=auth.uid() AND p.role='moderator')));
END $$;

CREATE OR REPLACE FUNCTION public.lf_item_create(
 p_category text,p_title text,p_description text,p_location_name text,
 p_latitude double precision,p_longitude double precision,p_photo_base64 text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid; v_photo bytea; v_source text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 IF p_photo_base64 IS NOT NULL THEN
  -- Limit encoded input before decoding; JPEG signature + end marker checked below and by table constraint.
  IF octet_length(p_photo_base64)>699052 OR p_photo_base64 !~ '^[A-Za-z0-9+/]*={0,2}$' THEN
   RAISE EXCEPTION '사진은 512KiB 이하의 JPEG여야 합니다' USING ERRCODE='22023';
  END IF;
  BEGIN v_photo:=decode(p_photo_base64,'base64');
  EXCEPTION WHEN others THEN RAISE EXCEPTION '올바른 JPEG 사진이 아닙니다' USING ERRCODE='22023'; END;
  IF octet_length(v_photo) NOT BETWEEN 4 AND 524288
     OR substring(v_photo FROM 1 FOR 3)<>decode('ffd8ff','hex')
     OR substring(v_photo FROM octet_length(v_photo)-1 FOR 2)<>decode('ffd9','hex') THEN
   RAISE EXCEPTION '사진은 512KiB 이하의 JPEG여야 합니다' USING ERRCODE='22023';
  END IF;
 END IF;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM public.community_profiles p WHERE p.user_id=auth.uid() AND p.role='moderator')
             THEN 'staff' ELSE 'user' END INTO v_source;
 INSERT INTO public.lf_items(source,author_id,category,title,description,location_name,latitude,longitude,photo_jpeg)
 VALUES(v_source,auth.uid(),p_category,btrim(p_title),coalesce(btrim(p_description),''),btrim(p_location_name),
        p_latitude,p_longitude,v_photo) RETURNING id INTO v_id;
 INSERT INTO public.lf_item_events(item_id,actor_id,kind) VALUES(v_id,auth.uid(),'created');
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.lf_claim_interest(p_item_id uuid,p_proof text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i public.lf_items%rowtype; v_id uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 IF p_proof IS NULL OR char_length(btrim(p_proof)) NOT BETWEEN 10 AND 500 THEN
  RAISE EXCEPTION '본인 확인 내용은 10~500자로 적어 주세요' USING ERRCODE='22023'; END IF;
 SELECT * INTO i FROM public.lf_items WHERE id=p_item_id FOR UPDATE;
 IF NOT FOUND OR i.status='received' OR i.author_id=auth.uid() THEN
  RAISE EXCEPTION '수령 의사를 등록할 수 없는 물건입니다' USING ERRCODE='22023'; END IF;
 INSERT INTO public.lf_item_claims(item_id,claimant_id,proof) VALUES(p_item_id,auth.uid(),btrim(p_proof))
 ON CONFLICT(item_id,claimant_id) DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id INTO v_id FROM public.lf_item_claims WHERE item_id=p_item_id AND claimant_id=auth.uid();
 ELSE
  INSERT INTO public.lf_item_events(item_id,actor_id,kind,detail)
  VALUES(p_item_id,auth.uid(),'claim_interest',jsonb_build_object('claim_id',v_id));
 END IF;
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.lf_claims_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_staff boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.community_profiles p WHERE p.user_id=auth.uid() AND p.role='moderator') INTO v_staff;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'item_id',c.item_id,'title',i.title,'proof',c.proof,'status',c.status,
  'mine',coalesce(c.claimant_id=auth.uid(),false),
  'can_verify',(v_staff OR coalesce(i.author_id=auth.uid(),false)) AND c.status='pending'
     AND i.status<>'received' AND coalesce(c.claimant_id<>auth.uid(),false),
  'created_at',c.created_at) ORDER BY c.created_at DESC,c.id),'[]'::jsonb)
 FROM public.lf_item_claims c JOIN public.lf_items i ON i.id=c.item_id
 WHERE c.claimant_id=auth.uid() OR i.author_id=auth.uid() OR v_staff);
END $$;

CREATE OR REPLACE FUNCTION public.lf_claim_verify(p_claim_id uuid,p_is_owner boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.lf_item_claims%rowtype; i public.lf_items%rowtype; v_item uuid; v_staff boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 IF p_is_owner IS NULL THEN RAISE EXCEPTION '확인 결과가 필요합니다' USING ERRCODE='22023'; END IF;
 SELECT item_id INTO v_item FROM public.lf_item_claims WHERE id=p_claim_id;
 -- Every mutator locks item then claim in this order, including completion.
 SELECT * INTO i FROM public.lf_items WHERE id=v_item FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO c FROM public.lf_item_claims WHERE id=p_claim_id FOR UPDATE;
 SELECT EXISTS(SELECT 1 FROM public.community_profiles p WHERE p.user_id=auth.uid() AND p.role='moderator') INTO v_staff;
 IF NOT (v_staff OR coalesce(i.author_id=auth.uid(),false)) OR c.claimant_id=auth.uid() THEN
  RAISE EXCEPTION '작성자 또는 담당자만 본인 확인할 수 있습니다' USING ERRCODE='42501'; END IF;
 IF c.status<>'pending' OR i.status='received' OR c.claimant_id IS NULL THEN RETURN false; END IF;
 UPDATE public.lf_item_claims SET status=CASE WHEN p_is_owner THEN 'accepted' ELSE 'rejected' END,
  verified_by=auth.uid(),verified_at=now(),updated_at=now() WHERE id=p_claim_id;
 INSERT INTO public.lf_item_events(item_id,actor_id,kind,detail)
 VALUES(i.id,auth.uid(),'claim_verified',jsonb_build_object('claim_id',c.id,'is_owner',p_is_owner));
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.lf_claim_complete(p_claim_id uuid,p_outcome text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.lf_item_claims%rowtype; i public.lf_items%rowtype; v_item uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 IF p_outcome IS NULL OR p_outcome NOT IN ('received','not_mine','not_received') THEN
  RAISE EXCEPTION '올바른 수령 결과가 필요합니다' USING ERRCODE='22023'; END IF;
 SELECT item_id INTO v_item FROM public.lf_item_claims WHERE id=p_claim_id;
 SELECT * INTO i FROM public.lf_items WHERE id=v_item FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO c FROM public.lf_item_claims WHERE id=p_claim_id FOR UPDATE;
 IF c.claimant_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION '요청한 본인만 수령 결과를 등록할 수 있습니다' USING ERRCODE='42501'; END IF;
 IF c.status=p_outcome THEN RETURN true; END IF; -- Safe retry after an uncertain network result.
 IF c.status NOT IN ('pending','accepted') OR i.status='received' THEN RETURN false; END IF;
 IF p_outcome='received' AND c.status<>'accepted' THEN
  RAISE EXCEPTION '담당자 본인 확인 후 수령 완료할 수 있습니다' USING ERRCODE='22023'; END IF;
 UPDATE public.lf_item_claims SET status=p_outcome,completed_at=now(),updated_at=now() WHERE id=p_claim_id;
 IF p_outcome='received' THEN
  UPDATE public.lf_items SET status='received',received_reason='claim_completed',updated_at=now() WHERE id=i.id;
  UPDATE public.lf_item_claims SET status='rejected',updated_at=now()
   WHERE item_id=i.id AND id<>p_claim_id AND status IN ('pending','accepted');
 END IF;
 INSERT INTO public.lf_item_events(item_id,actor_id,kind,detail)
 VALUES(i.id,auth.uid(),'claim_completed',jsonb_build_object('claim_id',c.id,'outcome',p_outcome));
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.lf_item_transfer(
 p_item_id uuid,p_location_name text,p_latitude double precision,p_longitude double precision)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i public.lf_items%rowtype; v_staff boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE='28000'; END IF;
 SELECT * INTO i FROM public.lf_items WHERE id=p_item_id FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT EXISTS(SELECT 1 FROM public.community_profiles p WHERE p.user_id=auth.uid() AND p.role='moderator') INTO v_staff;
 IF NOT (v_staff OR coalesce(i.author_id=auth.uid(),false)) THEN
  RAISE EXCEPTION '작성자 또는 담당자만 이관할 수 있습니다' USING ERRCODE='42501'; END IF;
 IF i.status='received' THEN RETURN false; END IF;
 UPDATE public.lf_items SET status='police',location_name=btrim(p_location_name),latitude=p_latitude,
  longitude=p_longitude,updated_at=now() WHERE id=p_item_id;
 INSERT INTO public.lf_item_events(item_id,actor_id,kind,detail)
 VALUES(i.id,auth.uid(),'transferred',jsonb_build_object('from',i.location_name,'to',btrim(p_location_name),
   'latitude',p_latitude,'longitude',p_longitude));
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.lf_sync_mysnu(p_items jsonb,p_complete boolean,p_run_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_fingerprint text; v_saved public.lf_sync_runs%rowtype; row jsonb;
 i public.lf_items%rowtype; v_id uuid; v_status text; v_registered timestamptz;
 v_seen text[] := ARRAY[]::text[]; v_inserted integer:=0; v_updated integer:=0; v_removed integer:=0;
 v_result jsonb; v_photo_url text;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN
  RAISE EXCEPTION 'Service role required' USING ERRCODE='42501'; END IF;
 IF p_run_id IS NULL OR p_complete IS NULL OR p_items IS NULL OR jsonb_typeof(p_items)<>'array' THEN
  RAISE EXCEPTION 'Snapshot array, completion flag and run UUID are required' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_items) NOT BETWEEN 1 AND 5000 OR octet_length(p_items::text)>10485760 THEN
  RAISE EXCEPTION 'Snapshot must contain 1..5000 records and be at most 10MiB' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(481923764::bigint);
 v_fingerprint:=encode(extensions.digest(p_items::text || ':' || p_complete::text,'sha256'),'hex');
 SELECT * INTO v_saved FROM public.lf_sync_runs WHERE run_id=p_run_id;
 IF FOUND THEN
  IF v_saved.fingerprint<>v_fingerprint THEN
   RAISE EXCEPTION 'Run UUID was already used for a different snapshot' USING ERRCODE='22023'; END IF;
  RETURN v_saved.result;
 END IF;
 FOR row IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  IF jsonb_typeof(row)<>'object'
     OR jsonb_typeof(row->'source_id') IS DISTINCT FROM 'string'
     OR char_length(btrim(row->>'source_id')) NOT BETWEEN 1 AND 128
     OR (row->>'source_id')<>btrim(row->>'source_id')
     OR (row->>'source_id')=ANY(v_seen)
     OR jsonb_typeof(row->'category') IS DISTINCT FROM 'string'
     OR jsonb_typeof(row->'title') IS DISTINCT FROM 'string'
     OR jsonb_typeof(row->'description') IS DISTINCT FROM 'string'
     OR jsonb_typeof(row->'location_name') IS DISTINCT FROM 'string'
     OR jsonb_typeof(row->'latitude') IS DISTINCT FROM 'number'
     OR jsonb_typeof(row->'longitude') IS DISTINCT FROM 'number'
     OR jsonb_typeof(row->'registered_at') IS DISTINCT FROM 'string'
     OR jsonb_typeof(row->'status') IS DISTINCT FROM 'string'
     OR (row->>'status') NOT IN ('stored','police')
     OR (row->>'category') NOT IN ('지갑','전자기기','학생증','우산','의류','가방','열쇠','기타')
     OR char_length(btrim(row->>'title')) NOT BETWEEN 2 AND 100
     OR char_length(row->>'description')>1000
     OR char_length(btrim(row->>'location_name')) NOT BETWEEN 2 AND 120
     OR (row->>'latitude')::double precision NOT BETWEEN 33 AND 39
     OR (row->>'longitude')::double precision NOT BETWEEN 124 AND 132
     OR (row->>'registered_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
     OR (row ? 'photo_url' AND row->'photo_url'<>'null'::jsonb AND jsonb_typeof(row->'photo_url')<>'string') THEN
   RAISE EXCEPTION 'Malformed or duplicate snapshot record' USING ERRCODE='22023';
  END IF;
  v_seen:=array_append(v_seen,row->>'source_id');
  v_registered:=(row->>'registered_at')::timestamptz;
  IF NOT isfinite(v_registered) OR v_registered>now()+interval '5 minutes' THEN
   RAISE EXCEPTION 'Invalid registration timestamp' USING ERRCODE='22023'; END IF;
  v_photo_url:=nullif(row->>'photo_url','');
  IF v_photo_url IS NOT NULL AND (char_length(v_photo_url)>2048
     OR v_photo_url !~ '^https://[A-Za-z0-9][A-Za-z0-9.:-]+(/[^[:space:]@]*)?$') THEN
   RAISE EXCEPTION 'Photo URL must use HTTPS without credentials' USING ERRCODE='22023'; END IF;
  SELECT * INTO i FROM public.lf_items WHERE source='mysnu' AND source_id=row->>'source_id' FOR UPDATE;
  IF FOUND AND i.status='received' THEN CONTINUE; END IF; -- Permanent tombstone; no automatic resurrection.
  IF NOT FOUND THEN
   INSERT INTO public.lf_items(source,source_id,category,title,description,location_name,latitude,longitude,
                              registered_at,status,photo_url)
   VALUES('mysnu',row->>'source_id',row->>'category',btrim(row->>'title'),btrim(row->>'description'),
    btrim(row->>'location_name'),(row->>'latitude')::double precision,(row->>'longitude')::double precision,
    v_registered,row->>'status',v_photo_url) RETURNING id INTO v_id;
   v_inserted:=v_inserted+1;
   INSERT INTO public.lf_item_events(item_id,kind,detail) VALUES(v_id,'source_created',jsonb_build_object('run_id',p_run_id));
  ELSE
   v_id:=i.id;
   -- A locally recorded police transfer is authoritative until a later source police record.
   v_status:=CASE WHEN i.status='police' THEN 'police' ELSE row->>'status' END;
   UPDATE public.lf_items SET category=row->>'category',title=btrim(row->>'title'),description=btrim(row->>'description'),
    location_name=CASE WHEN i.status='police' AND row->>'status'='stored' THEN i.location_name ELSE btrim(row->>'location_name') END,
    latitude=CASE WHEN i.status='police' AND row->>'status'='stored' THEN i.latitude ELSE (row->>'latitude')::double precision END,
    longitude=CASE WHEN i.status='police' AND row->>'status'='stored' THEN i.longitude ELSE (row->>'longitude')::double precision END,
    registered_at=v_registered,status=v_status,photo_url=v_photo_url,updated_at=now()
   WHERE id=v_id;
   v_updated:=v_updated+1;
   INSERT INTO public.lf_item_events(item_id,kind,detail) VALUES(v_id,'source_updated',jsonb_build_object('run_id',p_run_id));
  END IF;
 END LOOP;
 IF p_complete THEN
  FOR i IN SELECT * FROM public.lf_items WHERE source='mysnu' AND status<>'received'
           AND NOT(source_id=ANY(v_seen)) ORDER BY id FOR UPDATE LOOP
   UPDATE public.lf_items SET status='received',received_reason='source_removed',updated_at=now() WHERE id=i.id;
   UPDATE public.lf_item_claims SET status='rejected',updated_at=now() WHERE item_id=i.id AND status IN ('pending','accepted');
   INSERT INTO public.lf_item_events(item_id,kind,detail)
   VALUES(i.id,'source_removed',jsonb_build_object('run_id',p_run_id,'reason','source_removed'));
   v_removed:=v_removed+1;
  END LOOP;
 END IF;
 v_result:=jsonb_build_object('ok',true,'run_id',p_run_id,'complete',p_complete,'seen',cardinality(v_seen),
   'inserted',v_inserted,'updated',v_updated,'removed',v_removed);
 INSERT INTO public.lf_sync_runs(run_id,fingerprint,complete,result) VALUES(p_run_id,v_fingerprint,p_complete,v_result);
 RETURN v_result;
END $$;

-- Supabase may put pgcrypto in public or extensions. Resolve the schema at migration
-- time and pin a schema-qualified digest call without changing the function contract.
DO $$ DECLARE v_schema text; v_definition text; BEGIN
 SELECT n.nspname INTO v_schema FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='pgcrypto';
 IF v_schema IS NULL THEN RAISE EXCEPTION 'pgcrypto extension is required'; END IF;
 SELECT pg_get_functiondef('public.lf_sync_mysnu(jsonb,boolean,uuid)'::regprocedure) INTO v_definition;
 EXECUTE replace(v_definition,'extensions.digest(',format('%I.digest(',v_schema));
END $$;

-- Revoke every legacy and helper RPC first, including old lost reports/claim APIs.
-- Tables remain available only to the database owner for archival/export purposes.
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname LIKE 'lf\_%' ESCAPE '\' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.lf_centers_list() TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_items_list(),public.lf_item_detail(uuid),
 public.lf_item_create(text,text,text,text,double precision,double precision,text),
 public.lf_claim_interest(uuid,text),public.lf_claims_list(),public.lf_claim_verify(uuid,boolean),
 public.lf_claim_complete(uuid,text),public.lf_item_transfer(uuid,text,double precision,double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lf_sync_mysnu(jsonb,boolean,uuid) TO service_role;

COMMIT;
