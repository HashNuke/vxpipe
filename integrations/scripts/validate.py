"""Validate contributor definitions without fetching remote URLs."""
import json
import re
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

root = Path(__file__).resolve().parent.parent
schema = json.loads((root / "schema" / "schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
categories = {}
files = [root / "schema" / "template.json", *sorted(root.glob("*.json"))]
for path in files:
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,63}", path.stem):
        raise ValueError(f"Invalid integration filename: {path.name}")
    data = json.loads(path.read_text())
    validator.validate(data)
    ids = [category["id"] for category in data["categories"]]
    if len(set(ids)) != len(ids):
        raise ValueError(f"Duplicate category in {path.name}")
    for category in data["categories"]:
        previous = categories.setdefault(category["id"], category["name"])
        if previous != category["name"]:
            raise ValueError(f"Conflicting category name in {path.name}")
print(f"Validated {len(files) - 1} integrations and template.json")
