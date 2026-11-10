import copy
import json
import unittest
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker, ValidationError

ROOT = Path(__file__).resolve().parents[1]


class SetupMetadataTests(unittest.TestCase):
    def setUp(self):
        self.validator = Draft202012Validator(json.loads((ROOT / "schema" / "schema.json").read_text()), format_checker=FormatChecker())
        self.definition = json.loads((ROOT / "schema" / "template.json").read_text())
        for key in ("setup_url", "documentation_url", "setup_notes", "setup_note"):
            self.definition.pop(key, None)

    def test_mcp_setup_metadata_is_independently_optional(self):
        fields = {"setup_url": "https://example.com/setup", "documentation_url": "https://example.com/docs", "setup_notes": "Register an OAuth client first."}
        for mask in range(8):
            with self.subTest(mask=mask):
                definition = copy.deepcopy(self.definition)
                definition.update({key: value for index, (key, value) in enumerate(fields.items()) if mask & (1 << index)})
                self.validator.validate(definition)

    def test_invalid_metadata_is_rejected(self):
        for key in ("setup_url", "documentation_url"):
            for value in ("", None, "http://example.com", "javascript:alert(1)", "https://user:secret@example.com/"):
                with self.subTest(key=key, value=value), self.assertRaises(ValidationError):
                    self.validator.validate({**self.definition, key: value})
        for value in (None, "", "x" * 1001):
            with self.subTest(notes=value), self.assertRaises(ValidationError):
                self.validator.validate({**self.definition, "setup_notes": value})

    def test_provider_documentation_remains_required(self):
        definition = {**self.definition, "kind": "provider", "minimum_vxpipe_version": "0.1.0", "categories": [{"id": "ai", "name": "AI models"}], "connection": {"type": "builtin", "provider_id": "google"}}
        with self.assertRaises(ValidationError):
            self.validator.validate(definition)
        self.validator.validate({**definition, "documentation_url": "https://example.com/docs"})

    def test_new_definitions_use_plural_setup_notes(self):
        with self.assertRaises(ValidationError):
            self.validator.validate({**self.definition, "documentation_url": "https://example.com/docs", "setup_note": "Old field"})

    def test_only_native_providers_may_omit_a_declared_icon(self):
        native = {**self.definition, "kind": "provider", "minimum_vxpipe_version": "0.1.0", "documentation_url": "https://example.com/docs", "categories": [{"id": "ai", "name": "AI models"}], "connection": {"type": "builtin", "provider_id": "morse_code_api"}}
        native.pop("icon_url")
        self.validator.validate(native)
        mcp = copy.deepcopy(self.definition)
        mcp.pop("icon_url")
        with self.assertRaises(ValidationError):
            self.validator.validate(mcp)
        for value in ("", None, "http://example.com/icon.png", "https://user:secret@example.com/icon.png"):
            with self.subTest(icon=value), self.assertRaises(ValidationError):
                self.validator.validate({**native, "icon_url": value})
