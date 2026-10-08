"""Setup CLI contracts; external tools are fixtures, never live providers."""
import json
import os
from pathlib import Path
import shutil
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
        for tool in ("python3", "git", "bash"):
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
        for content in ("private-invalid", json.dumps(metadata | {"version": 100}),
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


if __name__ == "__main__":
    unittest.main()
