-- Supabase-specific deployment: daily at 03:20 Asia/Seoul (18:20 UTC).
-- Uses only the dedicated account/quest tables, never unrelated customer tables.
begin;
create extension if not exists pg_cron;
select cron.schedule('account-private-data-retention','20 18 * * *','select private.account_purge_expired();');
commit;
