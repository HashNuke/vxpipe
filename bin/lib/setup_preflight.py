"""Read-only developer-toolchain and PostgreSQL preflight."""
import re
import shutil
import subprocess


class SetupError(Exception):
    """An actionable error safe to show without external command output."""


def capture(arguments, *, cwd=None, environment=None, input_text=None):
    try:
        result = subprocess.run(arguments, cwd=cwd, env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=40, input=input_text)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def preflight(root):
    for command in ("git", "mix", "elixir", "erl", "node", "npm", "cargo", "cc", "c++",
                    "make", "pkg-config", "psql"):
        if not shutil.which(command):
            raise SetupError(f"missing required tool: {command}; install the development prerequisites")
    if capture(["git", "-C", str(root), "rev-parse", "--show-toplevel"]) != str(root):
        raise SetupError("run bin/setup from a Git checkout (root or linked worktree)")
    version = capture(["elixir", "--eval", 'IO.puts("#{System.version()}|#{System.otp_release()}")'])
    if not version or not re.fullmatch(r"1\.19\.\d+\|28", version):
        raise SetupError("Elixir 1.19 / Erlang OTP 28 are required; select the documented toolchain")
    node = capture(["node", "--version"])
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", node or "")
    if not match or tuple(map(int, match.groups())) < (22, 22, 0):
        raise SetupError("Node >=22.22.0 is required (Node 24 is the documented development baseline)")
    if capture(["pkg-config", "--exists", "openssl"]) is None:
        raise SetupError("OpenSSL development metadata is missing; install headers and pkg-config metadata")
