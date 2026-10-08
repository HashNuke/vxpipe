"""Setup CLI contracts; external tools are fixtures, never live providers."""
import base64
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]


class SetupTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="vxpipe-setup-")
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        self.root = self.base / "checkout"
        self.root.mkdir()
        shutil.copytree(REPOSITORY / "bin", self.root / "bin")
        self.fake = self.base / "tools"
        self.fake.mkdir()
        for tool in ("python3", "git", "bash", "dirname"):
            (self.fake / tool).symlink_to(shutil.which(tool))
        for tool in ("mix", "elixir", "erl", "node", "npm", "cargo", "cc", "c++", "make", "pkg-config", "psql"):
            self.tool(tool, "exit 0")
        self.tool("elixir", "printf '1.19.5|28\\n'")
        self.tool("node", "printf 'v24.0.0\\n'")
        self.tool("psql", "printf 't\\n'")
        self.environment = {key: os.environ[key] for key in ("HOME", "USER", "LANG") if key in os.environ}
        self.environment.update(PATH=str(self.fake), XDG_STATE_HOME=str(self.base / "state"))
        subprocess.run([str(self.fake / "git"), "init", "-q", "-b", "fixture", str(self.root)], check=True)

    def tool(self, name, body):
        target = self.fake / name
        target.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
        target.chmod(0o755)

    def setup(self, *arguments, root=None, **environment):
        return subprocess.run([str((root or self.root) / "bin/setup"), *arguments],
                              cwd=self.base, env=self.environment | environment,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def launch(self, name, **environment):
        return subprocess.run([str(self.root / "bin" / name)], cwd=self.base,
                              env=self.environment | environment, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True)

    def test_launchers_use_assigned_ports_and_explicit_overrides(self):
        self.assertEqual(self.setup().returncode, 0)
        ports = json.loads((self.root / ".vxpipe/worktree.json").read_text())["ports"]
        self.tool("mix", 'printf "console:%s" "$PORT"')
        self.tool("npm", 'printf "astro:%s" "$ASTRO_PORT"')
        self.assertEqual(self.launch("dev").stdout, f"console:{ports['console']}")
        self.assertEqual(self.launch("site-dev").stdout, f"astro:{ports['astro']}")
        (self.root / ".env").write_text("PORT=19501\n")
        self.assertEqual(self.launch("dev").stdout, "console:19501")
        self.assertEqual(self.launch("dev", PORT="19502").stdout, "console:19502")
        self.assertEqual(self.launch("site-dev", ASTRO_PORT="19503").stdout, "astro:19503")

    def test_launcher_refuses_occupied_or_live_port_before_command(self):
        self.assertEqual(self.setup().returncode, 0)
        self.tool("mix", 'printf "MIX_STARTED"')
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            result = self.launch("dev", PORT=str(listener.getsockname()[1]))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("occupied", result.stdout)
        self.assertNotIn("MIX_STARTED", result.stdout)
        result = self.launch("dev", PORT="4600")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("MIX_STARTED", result.stdout)

    def test_storybook_launcher_uses_reserved_port_and_keeps_console_origin(self):
        self.assertEqual(self.setup().returncode, 0)
        ports = json.loads((self.root / ".vxpipe/worktree.json").read_text())["ports"]
        binary = self.root / "node_modules/.bin"
        binary.mkdir(parents=True)
        command = binary / "storybook"
        command.write_text('#!/bin/bash\nprintf "%s\\n" "$@"\n')
        command.chmod(0o755)
        result = self.launch("storybook")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(f"--port\n{ports['storybook']}\n", result.stdout)
        self.assertIn("--exact-port", result.stdout)
        result = self.launch("storybook", STORYBOOK_PORT="19504")
        self.assertIn("--port\n19504\n", result.stdout)
        metadata = (self.root / ".vxpipe/worktree.json").read_bytes()
        result = subprocess.run([str(self.root / "bin/worktree-port"), "console"],
                                env=self.environment, capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), str(ports["console"]))
        self.assertEqual((self.root / ".vxpipe/worktree.json").read_bytes(), metadata)

    def test_optional_setup_checks_tools_and_runs_requested_steps(self):
        missing = self.setup("--with-lean")
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("lake", missing.stdout)
        self.assertFalse((self.root / ".vxpipe").exists())
        (self.root / "verification").mkdir()
        (self.root / "verification/lean-toolchain").write_text("leanprover/lean4:v4.34.1\n")
        self.tool("lake", "exit 0")
        self.tool("elan", '[[ "$PWD" == */verification ]] && [[ "$*" == "run leanprover/lean4:v4.34.1 lake build" ]]')
        self.tool("npm", '[[ "$*" == "--prefix vxpipe-docs ci" ]]')
        result = self.setup("--with-lean", "--with-docs")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Completed Astro dependencies", result.stdout)
        self.assertIn("Completed Lean build", result.stdout)
        self.tool("elan", "exit 3")
        failed = self.setup("--with-lean")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("Lean build failed", failed.stdout)
        self.assertNotIn("Ready", failed.stdout)

    def test_help_is_read_only(self):
        result = self.setup("--help")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Usage:", result.stdout)
        self.assertFalse((self.root / ".vxpipe").exists())

    def test_missing_tool_fails_before_metadata_or_mix(self):
        (self.fake / "mix").unlink()
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mix", result.stdout)
        self.assertFalse((self.root / ".vxpipe/worktree.json").exists())

    def test_unusable_postgres_has_safe_actionable_error(self):
        self.tool("psql", "printf 'postgres://private:secret@fixture/db\\n'; exit 2")
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PostgreSQL", result.stdout)
        self.assertNotIn("private:secret", result.stdout)
        self.assertFalse((self.root / ".vxpipe/worktree.json").exists())

    def test_insufficient_database_privileges_fail_before_initialization(self):
        self.tool("psql", "printf 'f\\n'")
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CREATEDB", result.stdout)
        self.assertFalse((self.root / ".vxpipe/worktree.json").exists())

    def test_unsupported_toolchain_is_explained(self):
        self.tool("node", "printf 'v18.0.0\\n'")
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Node", result.stdout)
        self.assertFalse((self.root / ".vxpipe/worktree.json").exists())

    def test_initialization_is_stable_across_reruns_and_branch_switches(self):
        first = self.setup()
        self.assertEqual(first.returncode, 0, first.stdout)
        path = self.root / ".vxpipe/worktree.json"
        metadata = json.loads(path.read_text())
        self.assertEqual(metadata["version"], 1)
        self.assertRegex(metadata["id"], r"^[a-f0-9]{32}$")
        self.assertEqual(metadata["root"], str(self.root))
        for name in ("dev", "test"):
            self.assertEqual(metadata["databases"][name], "vxpipe_" + metadata["id"] + "_" + name)
            self.assertLessEqual(len(metadata["databases"][name]), 63)
        subprocess.run([str(self.fake / "git"), "-C", str(self.root), "symbolic-ref", "HEAD", "refs/heads/another"], check=True)
        second = self.setup()
        self.assertEqual(second.returncode, 0, second.stdout)
        self.assertEqual(json.loads(path.read_text()), metadata)

    def test_concurrent_setup_keeps_one_identity(self):
        command = [str(self.root / "bin/setup")]
        first = subprocess.Popen(command, cwd=self.base, env=self.environment,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        second = self.setup()
        output, _ = first.communicate(timeout=20)
        self.assertEqual(first.returncode, 0, output)
        self.assertEqual(second.returncode, 0, second.stdout)
        metadata = json.loads((self.root / ".vxpipe/worktree.json").read_text())
        self.assertIn(metadata["id"], output)
        self.assertIn(metadata["id"], second.stdout)

    def test_copied_or_malformed_metadata_is_never_replaced(self):
        first = self.setup()
        self.assertEqual(first.returncode, 0, first.stdout)
        path = self.root / ".vxpipe/worktree.json"
        metadata = json.loads(path.read_text())
        for content in ("private-invalid", json.dumps(metadata | {"version": 100}), json.dumps(metadata | {"version": True}),
                        json.dumps(metadata | {"root": str(self.base / "another")})):
            path.write_text(content)
            result = self.setup()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("metadata", result.stdout)
            self.assertNotIn("private-invalid", result.stdout)
            self.assertEqual(path.read_text(), content)

    def test_leftover_unpublished_metadata_does_not_become_identity(self):
        directory = self.root / ".vxpipe"
        directory.mkdir()
        (directory / ".worktree.json.interrupted").write_text("incomplete")
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(json.loads((directory / "worktree.json").read_text())["version"], 1)

    def test_root_and_linked_checkout_discovery_from_another_directory(self):
        subprocess.run([str(self.fake / "git"), "-C", str(self.root), "add", "bin"], check=True)
        subprocess.run([str(self.fake / "git"), "-C", str(self.root), "-c", "user.name=Fixture",
                        "-c", "user.email=fixture@example.test", "commit", "-qm", "fixture"], check=True)
        linked = self.base / "linked"
        subprocess.run([str(self.fake / "git"), "-C", str(self.root), "worktree", "add", "-qb", "linked", str(linked)], check=True)
        first = self.setup()
        second = self.setup(root=linked)
        self.assertEqual(first.returncode, 0, first.stdout)
        self.assertEqual(second.returncode, 0, second.stdout)
        root_metadata = json.loads((self.root / ".vxpipe/worktree.json").read_text())
        linked_metadata = json.loads((linked / ".vxpipe/worktree.json").read_text())
        self.assertNotEqual(root_metadata["id"], linked_metadata["id"])
        self.assertNotEqual(root_metadata["databases"], linked_metadata["databases"])

    def test_dependencies_and_both_migrations_are_required_and_retryable(self):
        self.tool("mix", 'printf "%s %s\\n" "$MIX_ENV" "$*" >> "$SETUP_COMMAND_LOG"; [[ "$*" != "${SETUP_FAIL_STEP:-never}" ]]')
        log = self.base / "commands"
        result = self.setup(SETUP_COMMAND_LOG=str(log), SETUP_FAIL_STEP="ecto.migrate")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("migration", result.stdout)
        metadata = (self.root / ".vxpipe/worktree.json").read_text()
        result = self.setup(SETUP_COMMAND_LOG=str(log))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.root / ".vxpipe/worktree.json").read_text(), metadata)
        commands = log.read_text().splitlines()
        self.assertIn("dev deps.get", commands)
        self.assertIn("dev ecto.migrate", commands)
        self.assertIn("test ecto.migrate", commands)

    def test_explicit_connection_is_checked_before_writing_metadata(self):
        self.tool("psql", '[[ "${PGHOST:-}" == "remote.example.test" && "${PGUSER:-}" == "fixture" && "${PGPASSWORD:-}" == "synthetic-secret" ]] || exit 2; printf "t\\n"')
        result = self.setup(VXPIPE_DB_URL="postgres://fixture:synthetic-secret@remote.example.test/isolated",
                            VXPIPE_TEST_DATABASE_URL="postgres://fixture:synthetic-secret@remote.example.test/isolated_test")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("synthetic-secret", result.stdout)

    def test_shared_development_and_test_target_is_refused_before_migrations(self):
        result = self.setup(VXPIPE_DB_URL="postgres://localhost/shared", VXPIPE_TEST_DATABASE_URL="postgres://localhost/shared")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("same database", result.stdout)

    def test_unowned_database_is_refused_before_mix(self):
        self.tool("psql", 'query="$(</dev/stdin)"; if [[ "$query" == *pg_database* ]]; then printf "f\\n"; else printf "t\\n"; fi')
        self.tool("mix", 'exit 99')
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unowned", result.stdout)
        self.assertNotIn("Preparing Mix", result.stdout)

    def test_lockfile_change_is_reported_and_preserved_for_review(self):
        lock = self.root / "mix.lock"
        lock.write_text("original")
        self.tool("mix", 'printf "changed" > mix.lock')
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lockfile", result.stdout)
        self.assertEqual(lock.read_text(), "changed")

    def test_dependency_failure_retains_identity_and_does_not_migrate(self):
        self.tool("mix", 'printf "%s\\n" "$*" >> "$SETUP_COMMAND_LOG"; [[ "$*" != "deps.get" ]]')
        log = self.base / "commands"
        result = self.setup(SETUP_COMMAND_LOG=str(log))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(log.read_text().splitlines(), ["deps.get"])
        metadata = (self.root / ".vxpipe/worktree.json").read_text()
        self.tool("mix", "exit 0")
        self.assertEqual(self.setup().returncode, 0)
        self.assertEqual((self.root / ".vxpipe/worktree.json").read_text(), metadata)

    def test_failed_metadata_publication_leaves_no_half_identity(self):
        script = """
import sys
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, sys.argv[1])
from worktree_state import identity, setup_lock
root = Path(sys.argv[2])
with setup_lock(root):
    with patch('worktree_state.os.replace', side_effect=OSError('interrupted')):
        try:
            identity(root)
        except OSError:
            pass
        else:
            raise AssertionError('publication unexpectedly succeeded')
assert not (root / '.vxpipe/worktree.json').exists()
assert not list((root / '.vxpipe').glob('.worktree.json.*'))
"""
        subprocess.run([str(self.fake / "python3"), "-c", script, str(self.root / "bin/lib"), str(self.root)], check=True)
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_new_env_has_private_valid_secrets_and_rerun_does_not_rotate(self):
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout)
        path = self.root / ".env"
        self.assertTrue(path.exists(), "setup did not create .env")
        contents = path.read_text()
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        entries = dict(line.split("=", 1) for line in contents.splitlines() if line and not line.startswith("#"))
        keyring = json.loads(entries["VXPIPE_CREDENTIAL_KEYS"].strip("'"))
        self.assertEqual(len(base64.b64decode(keyring[entries["VXPIPE_CREDENTIAL_KEY_ID"]])), 32)
        self.assertGreaterEqual(len(entries["SECRET_KEY_BASE"]), 64)
        for secret in keyring.values():
            self.assertNotIn(secret, result.stdout)
        second = self.setup()
        self.assertEqual(second.returncode, 0, second.stdout)
        self.assertEqual(path.read_text(), contents)

    def test_existing_env_is_preserved_byte_for_byte(self):
        path = self.root / ".env"
        path.write_text("# existing settings\nSECRET_KEY_BASE=synthetic-existing-secret\n")
        contents = path.read_bytes()
        mode = path.stat().st_mode
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(path.read_bytes(), contents)
        self.assertEqual(path.stat().st_mode, mode)
        self.assertNotIn("synthetic-existing-secret", result.stdout)

    def test_assets_follow_dependencies_and_failures_never_report_readiness(self):
        self.tool("mix", 'printf "%s\\n" "$*" >> "$SETUP_COMMAND_LOG"; [[ "$*" != "${SETUP_FAIL_STEP:-never}" ]]')
        log = self.base / "commands"
        for failed in ("assets.setup", "assets.build"):
            result = self.setup(SETUP_COMMAND_LOG=str(log), SETUP_FAIL_STEP=failed)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("Ready", result.stdout)
        log.write_text("")
        result = self.setup(SETUP_COMMAND_LOG=str(log))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(log.read_text().splitlines()[:3], ["deps.get", "assets.setup", "assets.build"])
        self.assertIn("bin/dev", result.stdout)
        self.assertIn("mix test", result.stdout)
        self.assertIn("provider", result.stdout)

    def test_shared_build_overrides_fail_before_writing_metadata(self):
        for name in ("MIX_BUILD_PATH", "MIX_DEPS_PATH"):
            result = self.setup(**{name: str(self.base / "shared")})
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn(name, result.stdout)
            self.assertFalse((self.root / ".vxpipe/worktree.json").exists())

    def test_symlinked_mutable_output_is_refused(self):
        shared = self.base / "shared"
        shared.mkdir()
        for name in ("deps", "_build", "node_modules", "packages/core/dist", "apps/vxpipe_console/assets/node_modules", "verification/.lake"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(shared, target_is_directory=True)
            result = self.setup()
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("private", result.stdout)
            path.unlink()

    def test_build_logs_redact_environment_secrets(self):
        self.tool("mix", 'printf "%s\\n" "$SECRET_KEY_BASE" "$VXPIPE_DB_URL"; exit 1')
        result = self.setup(SECRET_KEY_BASE="synthetic-private-secret", VXPIPE_DB_URL="postgres://fixture:synthetic-password@localhost/private")
        self.assertNotEqual(result.returncode, 0)
        output = result.stdout + (self.root / ".vxpipe/setup.log").read_text()
        self.assertNotIn("synthetic-private-secret", output)
        self.assertNotIn("synthetic-password", output)

    def test_interrupt_stops_the_active_build_and_rerun_keeps_identity(self):
        ready = self.base / "ready"
        stopped = self.base / "stopped"
        os.mkfifo(ready)
        helper = self.fake / "mix"
        helper.write_text("""#!/usr/bin/env python3
import os, signal, sys
from pathlib import Path
def stop(signum, frame):
    Path(os.environ['SETUP_STOPPED']).touch()
    sys.exit(143)
signal.signal(signal.SIGTERM, stop)
with open(os.environ['SETUP_READY'], 'w') as stream:
    stream.write(str(os.getpid()) + '\\n')
signal.pause()
""")
        helper.chmod(0o755)
        process = subprocess.Popen([str(self.root / "bin/setup")], cwd=self.base,
                                   env=self.environment | {"SETUP_READY": str(ready), "SETUP_STOPPED": str(stopped)},
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        with ready.open() as stream:
            child = int(stream.read().strip())
        try:
            metadata = (self.root / ".vxpipe/worktree.json").read_text()
            process.terminate()
            output, _ = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 143, output)
            self.assertTrue(stopped.exists(), "setup left its build running")
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
            try:
                os.killpg(child, signal.SIGTERM)
            except ProcessLookupError:
                pass
        self.tool("mix", "exit 0")
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.root / ".vxpipe/worktree.json").read_text(), metadata)

    def another_checkout(self, name):
        root = self.base / name
        root.mkdir()
        shutil.copytree(self.root / "bin", root / "bin")
        subprocess.run([str(self.fake / "git"), "init", "-q", "-b", name, str(root)], check=True)
        return root

    def ports(self, root=None):
        return json.loads(((root or self.root) / ".vxpipe/worktree.json").read_text())["ports"]

    def test_concurrent_checkouts_reserve_distinct_stable_ports(self):
        other = self.another_checkout("other")
        first = subprocess.Popen([str(self.root / "bin/setup")], cwd=self.base, env=self.environment,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        second = self.setup(root=other)
        output, _ = first.communicate(timeout=20)
        self.assertEqual(first.returncode, 0, output)
        self.assertEqual(second.returncode, 0, second.stdout)
        first_ports, second_ports = self.ports(), self.ports(other)
        self.assertEqual(set(first_ports), {"console", "astro", "storybook"})
        self.assertTrue(set(first_ports.values()).isdisjoint(second_ports.values()))
        self.assertEqual(len(set(first_ports.values())), 3)
        self.assertNotIn(4600, list(first_ports.values()) + list(second_ports.values()))
        self.assertEqual(self.setup().returncode, 0)
        self.assertEqual(self.ports(), first_ports)
        self.assertFalse((self.base / "state/vxpipe/livetests").exists())

    def test_new_assignment_skips_occupied_listener(self):
        listener = socket.socket()
        try:
            try:
                listener.bind(("127.0.0.1", 4000))
                listener.listen()
            except OSError:
                pass  # An existing listener also makes the candidate unavailable.
            result = self.setup()
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotEqual(self.ports()["console"], 4000)
        finally:
            listener.close()

    def test_explicit_reassignment_preserves_identity_but_requires_old_listeners_to_stop(self):
        self.assertEqual(self.setup().returncode, 0)
        old = json.loads((self.root / ".vxpipe/worktree.json").read_text())
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", old["ports"]["console"]))
            listener.listen()
            result = self.setup("--reassign-ports")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stop", result.stdout)
        result = self.setup("--reassign-ports")
        self.assertEqual(result.returncode, 0, result.stdout)
        new = json.loads((self.root / ".vxpipe/worktree.json").read_text())
        self.assertEqual(old["id"], new["id"])
        self.assertEqual(old["databases"], new["databases"])
        self.assertTrue(set(old["ports"].values()).isdisjoint(new["ports"].values()))

    def test_abandoned_reservation_is_retained_while_any_listener_is_running(self):
        self.assertEqual(self.setup().returncode, 0)
        old_ports = self.ports()
        other = self.another_checkout("other")
        third = self.another_checkout("third")
        self.root.rename(self.base / "retired")
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", old_ports["console"]))
            listener.listen()
            result = self.setup(root=other)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertTrue(set(old_ports.values()).isdisjoint(self.ports(other).values()))
        result = self.setup(root=third)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.ports(third), old_ports)


if __name__ == "__main__":
    unittest.main()
