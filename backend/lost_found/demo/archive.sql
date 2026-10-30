-- Administrator-only, optional. Hides ONLY this test dataset; retains all history.
-- Does not delete rows, claims, or any real user/MySNU item. Safe to repeat.
WITH archived AS (
 UPDATE public.lf_items i SET status='received',received_reason='legacy_closed',updated_at=now()
 WHERE i.status<>'received' AND i.title LIKE '[테스트] %'
   AND i.id IN (SELECT ('d3f00000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid FROM generate_series(1,16) n)
   AND EXISTS(SELECT 1 FROM public.lf_item_events e WHERE e.item_id=i.id
              AND e.kind='demo_seed' AND e.detail->>'dataset'='lost-found-demo-v1')
 RETURNING i.id
), rejected AS (
 UPDATE public.lf_item_claims c SET status='rejected',updated_at=now()
 WHERE c.item_id IN (SELECT id FROM archived) AND c.status IN ('pending','accepted')
 RETURNING c.id
)
INSERT INTO public.lf_item_events(item_id,kind,detail)
SELECT id,'demo_archive','{"dataset":"lost-found-demo-v1","reason":"test_finished"}'::jsonb FROM archived;
