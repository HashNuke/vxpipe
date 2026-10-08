"""Persistent development-port reservations, shared by this user's checkouts."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import socket

from setup_preflight import SetupError
from worktree_state import atomic_json

DEFAULT_PORTS = {"console": 4000, "astro": 4321, "storybook": 6006}
LIVE_PORT = 4600


def valid_ports(ports):
    return (isinstance(ports, dict) and set(ports) == set(DEFAULT_PORTS)
            and all(type(port) is int and 1024 <= port <= 65535 and port != LIVE_PORT for port in ports.values())
            and len(set(ports.values())) == 3)


def port_available(port):
    for family, address in ((socket.AF_INET, "0.0.0.0"), (socket.AF_INET6, "::")):
        try:
            listener = socket.socket(family, socket.SOCK_STREAM)
        except OSError:
            if family == socket.AF_INET6:
                continue
            return False
        with listener:
            try:
                if family == socket.AF_INET6:
                    listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                listener.bind((address, port))
            except OSError:
                return False
    return True


@contextmanager
def allocator():
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    if not state.is_absolute():
        raise SetupError("XDG_STATE_HOME must be absolute so worktrees share the port registry")
    directory = state / "vxpipe/worktrees"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (directory / "ports.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield directory / "ports.json"


def read_registry(path):
    if not path.exists():
        return {"version": 1, "checkouts": {}}
    try:
        value = json.loads(path.read_text())
        if type(value["version"]) is not int or value["version"] != 1 or not isinstance(value["checkouts"], dict):
            raise ValueError()
        used = set()
        for record in value["checkouts"].values():
            if not isinstance(record["root"], str) or not valid_ports(record["ports"]):
                raise ValueError()
            if used.intersection(record["ports"].values()):
                raise ValueError()
            used.update(record["ports"].values())
        return value
    except (OSError, ValueError, KeyError, TypeError):
        raise SetupError("invalid shared worktree port registry; preserve it and repair the reservations before setup") from None


def assign_ports(root, metadata, reassign=False):
    with allocator() as path:
        registry = read_registry(path)
        records = registry["checkouts"]
        identifier = metadata["id"]
        existing = records.get(identifier)
        if existing and existing["root"] != str(root):
            raise SetupError("duplicate checkout ID in copied metadata; initialize this checkout with fresh metadata")
        # Never reclaim any part of a removed checkout's reservation while one of
        # its listeners is still bound. Existing checkout directories retain ports.
        abandoned = [key for key, record in records.items()
                     if key != identifier and not Path(record["root"]).exists()
                     and all(port_available(port) for port in record["ports"].values())]
        for key in abandoned:
            del records[key]
        previous = existing["ports"] if existing else metadata.get("ports")
        if previous is not None and not valid_ports(previous):
            raise SetupError("invalid worktree port metadata; repair it before setup")
        if reassign and previous and not all(port_available(port) for port in previous.values()):
            raise SetupError("stop existing listeners before using --reassign-ports")
        used = {LIVE_PORT}
        for key, record in records.items():
            if key != identifier:
                used.update(record["ports"].values())
        if previous and not reassign:
            if used.intersection(previous.values()):
                raise SetupError("saved ports conflict with another checkout; use --reassign-ports")
            if not existing and not all(port_available(port) for port in previous.values()):
                raise SetupError("saved ports are occupied without a reservation; stop listeners and use --reassign-ports")
            ports = previous
        else:
            if previous:
                used.update(previous.values())
            ports = {}
            for service, base in DEFAULT_PORTS.items():
                selected = next((port for port in range(base, 65536)
                                 if port not in used and port_available(port)), None)
                if selected is None:
                    raise SetupError("no free development ports remain; release retired reservations explicitly")
                ports[service] = selected
                used.add(selected)
        records[identifier] = {"root": str(root), "ports": ports}
        atomic_json(path, registry)
        metadata["ports"] = ports
        atomic_json(root / ".vxpipe/worktree.json", metadata)
        return ports
