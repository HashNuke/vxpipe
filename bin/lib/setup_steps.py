"""Run local build/setup steps with private, redacted logs and failure propagation."""
import json
import os
import re
import signal
import subprocess

from setup_preflight import SetupError


def redact(output, environment):
    for name, value in environment.items():
        if any(word in name for word in ("PASSWORD", "SECRET", "TOKEN", "KEY", "URL")) and len(value) > 3:
            output = output.replace(value, "[redacted]")
            if name == "VXPIPE_CREDENTIAL_KEYS":
                try:
                    for secret in json.loads(value).values():
                        output = output.replace(secret, "[redacted]")
                except (ValueError, AttributeError, TypeError):
                    pass
    return re.sub(r"postgres(?:ql)?://[^\s'\"<>]+", "[redacted database URL]", output)


def run_step(root, environment, arguments, label):
    print(f"Preparing {label}…", flush=True)
    settings = os.environ | {"MIX_ENV": environment}
    lockfiles = [root / name for name in ("mix.lock", "package-lock.json",
                 "apps/vxpipe_console/assets/package-lock.json", "vxpipe-docs/package-lock.json")]
    before = {path: path.read_bytes() if path.exists() else None for path in lockfiles}
    process = subprocess.Popen(arguments, cwd=root, env=settings, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        output, _ = process.communicate()
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        raise
    log = root / ".vxpipe/setup.log"
    descriptor = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(f"\n{label}\n{redact(output, settings)}\n")
    changed = [path for path, content in before.items()
               if (path.read_bytes() if path.exists() else None) != content]
    if changed:
        raise SetupError("a lockfile changed unexpectedly; review the diff before rerunning setup (changes were preserved)")
    if process.returncode:
        raise SetupError(f"{label} failed; inspect .vxpipe/setup.log, fix the cause, then rerun bin/setup")
    print(f"Completed {label}", flush=True)
