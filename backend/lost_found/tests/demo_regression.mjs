import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const db = new PGlite({ extensions: { pgcrypto } });
const owner = '10000000-0000-0000-0000-000000000001';
const claimant = '10000000-0000-0000-0000-000000000002';
const seed = await readFile(new URL('../demo/seed.sql', import.meta.url), 'utf8');
const archive = await readFile(new URL('../demo/archive.sql', import.meta.url), 'utf8');
const scalar = async sql => (await db.query(sql)).rows[0].value;
const demoWhere = "id BETWEEN 'd3f00000-0000-4000-8000-000000000001' AND 'd3f00000-0000-4000-8000-000000000016'";
const seedAs = async id => db.exec(`BEGIN; SELECT set_config('chajajwo.demo_owner_id','${id}',true); ${seed} COMMIT;`);
const asUser = async id => db.exec(`SELECT set_config('request.jwt.claim.sub','${id}',false); SELECT set_config('request.jwt.claim.role','authenticated',false);`);
try {
  for (const path of ['./bootstrap.sql', '../../community/001_community_mvp.sql', '../001_lost_found_mvp.sql', './legacy_seed.sql', '../002_unified_found_items.sql']) {
    await db.exec(await readFile(new URL(path, import.meta.url), 'utf8'));
  }
  await assert.rejects(db.exec(seed), /existing test user/);
  await seedAs(owner);
  assert.equal(Number(await scalar(`SELECT count(*) AS value FROM public.lf_items WHERE ${demoWhere}`)), 16);
  assert.deepEqual((await db.query(`SELECT status,count(*)::int AS n FROM public.lf_items WHERE ${demoWhere} GROUP BY status ORDER BY status`)).rows,
    [{status:'police',n:2},{status:'received',n:1},{status:'stored',n:13}]);
  assert.equal(Number(await scalar(`SELECT count(DISTINCT category) AS value FROM public.lf_items WHERE ${demoWhere}`)), 8);
  assert.equal(Number(await scalar(`SELECT count(*) AS value FROM public.lf_items WHERE ${demoWhere} AND status='stored' AND latitude=37.46328 AND longitude=126.95015`)), 6);
  assert.equal(Number(await scalar(`SELECT count(*) AS value FROM public.lf_items WHERE ${demoWhere} AND (title NOT LIKE '[테스트] %' OR source<>'user' OR source_id IS NOT NULL)`)), 0);
  await seedAs(owner);
  assert.equal(Number(await scalar("SELECT count(*) AS value FROM public.lf_item_events WHERE kind='demo_seed'")), 16);
  console.log('PASS 16 labeled items, all categories, 6 same-location items, idempotent seed');
  await asUser(claimant);
  await db.exec('SET ROLE authenticated');
  const listed = await scalar('SELECT public.lf_items_list() AS value');
  assert.equal(listed.filter(x=>x.title.startsWith('[테스트]')).length, 15);
  const item = 'd3f00000-0000-4000-8000-000000000001';
  const claim = await scalar(`SELECT public.lf_claim_interest('${item}','가상 지갑 안쪽에 별 모양 스티커가 있습니다') AS value`);
  await asUser(owner);
  await db.exec(`SELECT public.lf_claim_verify('${claim}',true)`);
  await asUser(claimant);
  await db.exec(`SELECT public.lf_claim_complete('${claim}','received')`);
  const pendingClaim = await scalar("SELECT public.lf_claim_interest('d3f00000-0000-4000-8000-000000000002','가상 이어폰 케이스 안쪽에 표시가 있습니다') AS value");
  await db.exec('RESET ROLE');
  await seedAs(owner);
  assert.equal(await scalar(`SELECT status AS value FROM public.lf_items WHERE id='${item}'`), 'received');
  console.log('PASS member listing and real claim/receipt RPCs; seeding never resurrects received items');
  await db.exec(archive);
  await db.exec(archive);
  assert.equal(await scalar(`SELECT status AS value FROM public.lf_item_claims WHERE id='${pendingClaim}'`), 'rejected');
  assert.equal(await scalar(`SELECT status AS value FROM public.lf_item_claims WHERE id='${claim}'`), 'received');
  assert.equal(Number(await scalar(`SELECT count(*) AS value FROM public.lf_items WHERE ${demoWhere} AND status<>'received'`)), 0);
  assert.equal(await scalar("SELECT status AS value FROM public.lf_items WHERE id='20000000-0000-0000-0000-000000000001'"), 'stored');
  console.log('PASS repeatable archive hides only test items; real records preserved');
} finally { await db.close(); }
