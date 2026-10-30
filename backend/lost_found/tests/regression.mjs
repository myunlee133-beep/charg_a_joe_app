import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

// A fresh PostgreSQL WASM database in memory; never reads a production URL or key.
const db = new PGlite({ extensions: { pgcrypto } });
const sqlFiles = [
  './bootstrap.sql', '../../community/001_community_mvp.sql',
  '../001_lost_found_mvp.sql', './legacy_seed.sql',
    '../002_unified_found_items.sql', '../003_shuttle_storage_center.sql', './regression.sql'
];
try {
  for (const path of sqlFiles) {
    const url = new URL(path, import.meta.url);
    await db.exec(await readFile(url, 'utf8'));
    process.stdout.write(`PASS ${fileURLToPath(url)}\n`);
  }
  // Reapplying the migration must retain schema and migrated identifiers.
  await db.exec(await readFile(new URL('../002_unified_found_items.sql', import.meta.url), 'utf8'));
  process.stdout.write('PASS migration reapplication\n');
  await db.exec(await readFile(new URL('../003_shuttle_storage_center.sql', import.meta.url), 'utf8'));
  const centers = (await db.query('SELECT public.lf_centers_list() AS centers')).rows[0].centers;
  const shuttle = centers.filter(c => c.id === 'snu331');
  if (centers.length !== 3 || shuttle.length !== 1 || shuttle[0].latitude !== 37.44937 ||
      shuttle[0].longitude !== 126.95014 || !shuttle[0].custody_note.includes('2014')) {
    throw new Error('Shuttle custody point missing, duplicated or incorrectly located');
  }
  process.stdout.write('PASS shuttle center and idempotent data migration\n');
  // Check actual SQL grants as member, independently of security-definer guards.
  await db.exec('SET ROLE authenticated');
  for (const forbidden of [
    'SELECT * FROM public.lf_items',
    'SELECT public.lf_lost_list()',
    "SELECT public.lf_sync_mysnu('[]',true,gen_random_uuid())"
  ]) {
    let denied = false;
    try { await db.exec(forbidden); }
    catch (error) { if (error.code === '42501') denied = true; else throw error; }
    if (!denied) throw new Error(`Member unexpectedly accessed: ${forbidden}`);
  }
  await db.exec('RESET ROLE');
  process.stdout.write('PASS actual role permission boundaries\n');
} finally {
  await db.close();
}
