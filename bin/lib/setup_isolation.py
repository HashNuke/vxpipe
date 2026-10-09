"""Reject shared mutable dependency and output directories before setup starts."""
import os
from pathlib import Path

from setup_preflight import SetupError


def check_isolation(root):
    directories = [root / name for name in (
        ".vxpipe", "deps", "_build", "node_modules", "tmp", "storybook-static",
        "apps/vxpipe_console/assets/node_modules", "apps/vxpipe_console/assets/storybook-static",
        "apps/vxpipe_console/priv/static/assets", "verification/.lake")]
    directories.extend(path for package in (root / "packages").glob("*")
                       for path in (package / "dist", package / "node_modules", package / "storybook-static"))
    for variable in ("MIX_BUILD_PATH", "MIX_DEPS_PATH"):
        value = os.environ.get(variable)
        if value:
            path = Path(value)
            if not path.is_absolute():
                path = root / path
            if not path.resolve().is_relative_to(root):
                raise SetupError(f"{variable} points outside this checkout; unset it or select a private directory")
            directories.append(path)
    for path in directories:
        current = path
        while current != root and current != current.parent:
            if current.is_symlink():
                raise SetupError("mutable dependency/output directories must be private, not symlinked; remove the shared mapping explicitly before setup")
            current = current.parent
