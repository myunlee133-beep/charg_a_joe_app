"""Execution contract: direct source, preview first, modern server credentials."""
import contextlib
import io
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sync_mysnu as sync


class ExecutionTests(unittest.TestCase):
    def test_default_source_is_the_actual_portal(self):
        with self.assertRaisesRegex(sync.SyncError, "portal_session_required"):
            sync.run({}, dry_run=True)

    def test_cli_defaults_to_no_database_writes(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, "argv", ["sync_mysnu.py"]), \
             patch.object(sync, "run", return_value={"items": 1}) as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, sync.main())
        self.assertTrue(run.call_args.kwargs["dry_run"])

    def test_modern_secret_key_is_not_a_bearer_jwt(self):
        settings = {"SUPABASE_URL": "https://fixture.supabase.co", "SUPABASE_SECRET_KEY": "sb_secret_synthetic_test_key"}
        with patch.object(sync, "request_json", return_value={"ok": True}) as rpc:
            sync.synchronize([], True, settings, dry_run=False)
        headers = rpc.call_args.kwargs["headers"]
        self.assertEqual("sb_secret_synthetic_test_key", headers["apikey"])
        self.assertNotIn("Authorization", headers)

    def test_legacy_server_key_still_uses_bearer_header(self):
        _, headers = sync.server_configuration({"SUPABASE_URL": "https://fixture.supabase.co",
                                                "SUPABASE_SERVICE_ROLE_KEY": "synthetic-legacy-key"})
        self.assertEqual("Bearer synthetic-legacy-key", headers["Authorization"])

    def test_publishable_key_is_rejected_before_collecting_source(self):
        settings = {"SUPABASE_URL": "https://fixture.supabase.co", "SUPABASE_SECRET_KEY": "sb_publishable_synthetic"}
        with patch.dict(os.environ, settings, clear=True), patch.object(sys, "argv", ["sync_mysnu.py", "--apply"]), \
             patch.object(sync, "run") as run, contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(1, sync.main())
        run.assert_not_called()
        self.assertIn("service_role_key_required", errors.getvalue())
        self.assertNotIn("sb_publishable_synthetic", errors.getvalue())

    def test_prompt_requires_a_terminal_and_never_echoes_secrets(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, "argv", ["sync_mysnu.py", "--prompt-session"]), \
             patch.object(sys.stdin, "isatty", return_value=False), patch.object(sync.getpass, "getpass") as prompt, \
             patch.object(sync, "run") as run, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(1, sync.main())
        prompt.assert_not_called()
        run.assert_not_called()

    def test_prompted_credentials_are_ephemeral_and_apply_is_explicit(self):
        settings = {"SUPABASE_URL": "https://fixture.supabase.co"}
        with patch.dict(os.environ, settings, clear=True), patch.object(sys, "argv", ["sync_mysnu.py", "--prompt-session", "--apply"]), \
             patch.object(sys.stdin, "isatty", return_value=True), patch.object(sys.stderr, "isatty", return_value=True), \
             patch.object(sync.getpass, "getpass", side_effect=["session=synthetic", "sb_secret_synthetic"]) as prompt, \
             patch.object(sync, "run", return_value={"items": 1}) as run, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(0, sync.main())
            self.assertNotIn("MYSNU_COOKIE", os.environ)
            self.assertNotIn("SUPABASE_SECRET_KEY", os.environ)
        self.assertEqual(2, prompt.call_count)
        self.assertEqual("session=synthetic", run.call_args.args[0]["MYSNU_COOKIE"])
        self.assertFalse(run.call_args.kwargs["dry_run"])
        self.assertNotIn("synthetic", output.getvalue())

    def test_explicit_export_mode_is_preserved(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, "argv", ["sync_mysnu.py", "--source-mode", "export"]), \
             patch.object(sync, "run", return_value={"items": 1}) as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, sync.main())
        self.assertEqual("export", run.call_args.args[0]["MYSNU_SOURCE_MODE"])
        self.assertTrue(run.call_args.kwargs["dry_run"])


if __name__ == "__main__":
    unittest.main()
