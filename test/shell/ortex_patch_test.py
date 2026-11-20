"""Verify exact pinned native-thread patch preparation and preservation."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class OrtexPatchTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix='vxpipe-ortex-patch-')
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        (self.root / 'bin').mkdir()
        (self.root / 'deps').mkdir()
        shutil.copy2(ROOT / 'bin/patch-ortex', self.root / 'bin/patch-ortex')
        shutil.copytree(ROOT / 'patches/ortex', self.root / 'patches/ortex')
        subprocess.run(['git', 'clone', '--quiet', '--shared', str(ROOT / 'deps/ortex'),
                        str(self.root / 'deps/ortex')], check=True, capture_output=True)

    def apply(self):
        return subprocess.run([str(self.root / 'bin/patch-ortex')], capture_output=True, text=True)

    def test_fresh_and_repeated_application(self):
        for _ in range(2):
            result = self.apply()
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_unknown_sources_are_preserved(self):
        source = self.root / 'deps/ortex/native/ortex/src/model.rs'
        modified = source.read_bytes() + b'\n// local change\n'
        source.write_bytes(modified)
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual(source.read_bytes(), modified)

    def test_modified_patch_is_rejected_before_source_changes(self):
        patch = self.root / 'patches/ortex/session-threads.patch'
        patch.write_bytes(patch.read_bytes() + b'\n')
        source = self.root / 'deps/ortex/native/ortex/src/model.rs'
        before = source.read_bytes()
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual(source.read_bytes(), before)

    def test_wrong_revision_is_rejected(self):
        import json
        manifest = self.root / 'patches/ortex/session-threads.json'
        data = json.loads(manifest.read_text())
        data['revision'] = '0' * 40
        manifest.write_text(json.dumps(data))
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('revision', result.stderr)

    def test_mixed_states_are_preserved(self):
        self.assertEqual(self.apply().returncode, 0)
        dependency = self.root / 'deps/ortex'
        path = 'lib/ortex.ex'
        original = subprocess.check_output(['git', 'show', 'HEAD:' + path], cwd=dependency)
        (dependency / path).write_bytes(original)
        self.assertNotEqual(self.apply().returncode, 0)
        self.assertEqual((dependency / path).read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
