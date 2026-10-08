"""Versioned non-secret checkout identity and atomic local metadata writes."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import tempfile

from setup_preflight import SetupError


def atomic_json(path, value):
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


@contextmanager
def setup_lock(root):
    directory = root / ".vxpipe"
    if directory.is_symlink():
        raise SetupError(".vxpipe must be private to this checkout; remove its symlink explicitly")
    directory.mkdir(mode=0o700, exist_ok=True)
    with (directory / "setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def read_identity(root):
    path = root / ".vxpipe/worktree.json"
    if path.exists():
        try:
            value = json.loads(path.read_text())
            identifier = value["id"]
            if (type(value["version"]) is not int or value["version"] != 1 or value["root"] != str(root)
                    or not isinstance(identifier, str)
                    or not re.fullmatch(r"[a-f0-9]{32}", identifier)
                    or value["databases"] != database_names(identifier)):
                raise ValueError()
        except (OSError, ValueError, KeyError, TypeError):
            raise SetupError("invalid, unsupported or copied worktree metadata; preserve it for recovery and run setup with fresh metadata in this checkout") from None
        return value
    return None


def identity(root):
    value = read_identity(root)
    if value is not None:
        return value
    path = root / ".vxpipe/worktree.json"
    identifier = secrets.token_hex(16)
    value = {"version": 1, "id": identifier, "root": str(root), "databases": database_names(identifier)}
    atomic_json(path, value)
    return value


def database_names(identifier):
    return {environment: f"vxpipe_{identifier}_{environment}" for environment in ("dev", "test")}
