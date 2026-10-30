-- Run after 001 and before 002 in the isolated test database.
INSERT INTO auth.users(id) VALUES
 ('10000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002');
INSERT INTO public.community_profiles(user_id,nickname,role) VALUES
 ('10000000-0000-0000-0000-000000000001','테스트작성자','member'),
 ('10000000-0000-0000-0000-000000000002','테스트수령자','member');
INSERT INTO public.lf_found_items(id,author_id,category,title,description,location_name,latitude,longitude,found_at,custody,status) VALUES
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 '지갑','기존 지갑','이전 버전 등록','학생회관',37.46,126.95,now(),'finder','active'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
 '열쇠','기존 수령 열쇠','이전 버전 완료','학생회관',37.46,126.95,now(),'finder','returned');
INSERT INTO public.lf_claims(id,found_id,claimant_id,proof_note,status) VALUES
 ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000002','안쪽에 이름표가 붙어 있습니다','accepted');
