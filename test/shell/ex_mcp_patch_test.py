"""Verify the pinned transport patch against a clean local dependency checkout."""
from pathlib import Path
import shutil
import json
import hashlib
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]


class ExMCPPatchTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="vxpipe-ex-mcp-patch-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        (self.root / "bin").mkdir()
        (self.root / "deps").mkdir()
        shutil.copy2(REPOSITORY / "bin/patch-ex-mcp", self.root / "bin/patch-ex-mcp")
        shutil.copytree(REPOSITORY / "patches", self.root / "patches")
        subprocess.run(
            ["git", "clone", "--quiet", "--shared", str(REPOSITORY / "deps/ex_mcp"),
             str(self.root / "deps/ex_mcp")], check=True, capture_output=True,
        )

    def patch(self):
        return subprocess.run([str(self.root / "bin/patch-ex-mcp")],
                              capture_output=True, text=True)

    def test_clean_application_and_idempotence(self):
        result = self.patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("applied and verified", result.stdout)
        result = self.patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("patch verified", result.stdout)

    def test_preserves_unrecognized_dependency_changes(self):
        source = self.root / "deps/ex_mcp/lib/ex_mcp/transport/http.ex"
        modified = source.read_bytes() + b"\n# local modification\n"
        source.write_bytes(modified)
        result = self.patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("preserve changes", result.stderr)
        self.assertEqual(source.read_bytes(), modified)

    def test_rejects_modified_patch(self):
        patch = self.root / "patches/ex_mcp/runtime-request-credentials.patch"
        patch.write_bytes(patch.read_bytes() + b"\n")
        result = self.patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum differs", result.stderr)

    def test_upgrades_the_previous_reviewed_patch_without_discarding_changes(self):
        manifest = json.loads((self.root / "patches/ex_mcp/runtime-request-credentials.json").read_text())
        dependency = self.root / "deps/ex_mcp"
        patch = self.root / "patches/ex_mcp/runtime-request-credentials.patch"
        upgrade = patch.parent / manifest["previous"]["patch_file"]
        # Derive the declared prior state without needing history in shallow CI clones.
        subprocess.run(["git", "apply", str(patch)], cwd=dependency, check=True, capture_output=True)
        subprocess.run(["git", "apply", "--reverse", str(upgrade)],
                       cwd=dependency, check=True, capture_output=True)
        self.assertEqual({name: hashlib.sha256((dependency / name).read_bytes()).hexdigest()
                          for name in manifest["files"]}, manifest["previous"]["files"])
        result = self.patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("applied and verified", result.stdout)
        self.assertEqual(self.patch().returncode, 0)

    def test_rejects_tampered_upgrade_patch_without_changing_sources(self):
        manifest = json.loads((self.root / "patches/ex_mcp/runtime-request-credentials.json").read_text())
        upgrade = self.root / "patches/ex_mcp" / manifest["previous"]["patch_file"]
        upgrade.write_bytes(upgrade.read_bytes() + b"\n")
        source = self.root / "deps/ex_mcp/lib/ex_mcp/transport/http.ex"
        before = source.read_bytes()
        self.assertNotEqual(self.patch().returncode, 0)
        self.assertEqual(source.read_bytes(), before)

    def test_rejects_a_different_dependency_revision(self):
        dependency = self.root / "deps/ex_mcp"
        subprocess.run(["git", "checkout", "--quiet", "--detach", "HEAD^"],
                       cwd=dependency, check=True, capture_output=True)
        source = dependency / "lib/ex_mcp/transport/http.ex"
        before = source.read_bytes()
        result = self.patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("revision or patch checksum differs", result.stderr)
        self.assertEqual(source.read_bytes(), before)

    def test_preserves_mixed_original_and_patched_sources(self):
        self.assertEqual(self.patch().returncode, 0)
        dependency = self.root / "deps/ex_mcp"
        name = "lib/ex_mcp/transport/http.ex"
        original = subprocess.check_output(["git", "show", "HEAD:" + name], cwd=dependency)
        source = dependency / name
        source.write_bytes(original)
        stream = dependency / "lib/ex_mcp/transport/sse_client.ex"
        patched_stream = stream.read_bytes()
        result = self.patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("preserve changes", result.stderr)
        self.assertEqual(source.read_bytes(), original)
        self.assertEqual(stream.read_bytes(), patched_stream)


if __name__ == "__main__":
    unittest.main()
