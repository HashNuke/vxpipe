#!/usr/bin/env python3
"""Verify exact-source, repeatable preparation of the ReqLLM dependency patch."""
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
APPLY = runpy.run_path(str(ROOT / "bin/patch-req-llm"))["apply_patch"]


class ReqLLMPatchTest(unittest.TestCase):
    def test_apply_repeat_and_preserve_unknown_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "patches/req_llm", root / "patches/req_llm")
            (root / "mix.lock").write_text((ROOT / "mix.lock").read_text())
            name = "lib/req_llm/providers/google.ex"
            source = root / "deps/req_llm" / name
            source.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / "deps/req_llm" / name, source)
            patch = root / "patches/req_llm/google-native-signatures.patch"
            manifest = json.loads(patch.with_suffix(".json").read_text())
            digest = runpy.run_path(str(ROOT / "bin/patch-req-llm"))["digest"]
            if digest(source) == manifest["files"][name]["patched"]:
                subprocess.run(["patch", "--batch", "-R", "-p1", "-i", str(patch)],
                               cwd=root / "deps/req_llm", check=True, capture_output=True)
            self.assertEqual(digest(source), manifest["files"][name]["original"])
            APPLY(root)
            self.assertEqual(digest(source), manifest["files"][name]["patched"])
            APPLY(root)
            source.write_text(source.read_text() + "\n# local unreviewed edit\n")
            changed = source.read_bytes()
            with self.assertRaisesRegex(ValueError, "sources differ"):
                APPLY(root)
            self.assertEqual(source.read_bytes(), changed)
            patch.write_text(patch.read_text() + "\n")
            with self.assertRaisesRegex(ValueError, "checksum differs"):
                APPLY(root)
            self.assertEqual(source.read_bytes(), changed)


if __name__ == "__main__":
    unittest.main()
