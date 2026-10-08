"""Create private local secrets once; existing user configuration is authoritative."""
import base64
import json
import os
from pathlib import Path
import secrets
import tempfile


def initialize_environment(root, identifier):
    path = root / ".env"
    if path.exists() or path.is_symlink():
        print("Preserved existing .env", flush=True)
        return
    key_id = f"local-{identifier[:12]}"
    keyring = json.dumps({key_id: base64.b64encode(secrets.token_bytes(32)).decode()}, separators=(",", ":"))
    contents = ("# Local platform secrets generated once by bin/setup. Do not commit.\n"
                f"VXPIPE_CREDENTIAL_KEY_ID={key_id}\n"
                f"VXPIPE_CREDENTIAL_KEYS='{keyring}'\n"
                f"SECRET_KEY_BASE={base64.b64encode(secrets.token_bytes(64)).decode()}\n")
    descriptor, temporary = tempfile.mkstemp(prefix=".env.setup.", dir=root / ".vxpipe")
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            print("Preserved existing .env", flush=True)
        else:
            print("Created private .env with local platform secrets", flush=True)
    finally:
        Path(temporary).unlink(missing_ok=True)
