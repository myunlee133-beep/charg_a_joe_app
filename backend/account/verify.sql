select jsonb_build_object(
 'auth_user_count',(select count(*) from auth.users),
 'account_profile_count',(select count(*) from public.account_profiles),
 'unmapped_users',(select count(*) from auth.users u left join public.account_profiles p on p.user_id=u.id where p.user_id is null),
 'active_policy_count',(select count(*) from public.account_policy_versions where active),
 'key_foreign_keys',(select jsonb_agg(conname) from pg_constraint where contype='f' and conrelid in ('public.quests'::regclass,'public.quest_participations'::regclass,'private.quest_transactions'::regclass)),
 'client_private_access',has_schema_privilege('authenticated','private','USAGE'),
 'client_quest_table_write',has_table_privilege('authenticated','public.quests','UPDATE'),
 'anon_accept_rpc',has_function_privilege('anon','public.quest_accept(uuid)','EXECUTE'),
 'disabled_rls_count',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and not c.relrowsecurity and
 ((n.nspname='public' and c.relname in ('account_profiles','account_policy_versions','quests','quest_participations')) or
 (n.nspname='private' and c.relname in ('account_subjects','account_consents','quest_transactions','quest_transfer_details','quest_events')))),
 'retention_job',(select jsonb_build_object('schedule',schedule,'active',active) from cron.job where jobname='account-private-data-retention')
) as account_setup_verification;
