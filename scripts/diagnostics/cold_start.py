"""Bounded one-time readiness handshake while sampling room preparation."""
import json
import os
import select
import time
from resource_schedule import COLD_MAX_START_NS


def prepare(resources, write, ready, *, start_ready=lambda _: True, clock=time.monotonic_ns):
    start = clock()
    resources.start_cold(start)
    emit = lambda event: write(b'\3' + json.dumps(event).encode())
    for stage in (ready, start_ready):
        deadline = start + (15_000_000_000 if stage is ready else COLD_MAX_START_NS)
        while True:
            resources.advance(clock(), wait=lambda _: None, emit=emit)
            now = clock()
            if now >= deadline:
                raise ValueError('cold STT readiness deadline' if stage is ready else 'cold generator lifetime limit')
            remaining = min(resources.next_ns, deadline) - now
            if remaining <= 0:
                continue
            if stage(remaining / 1e9):
                if clock() > deadline:
                    raise ValueError('late cold control acknowledgement')
                if stage is ready:
                    resources.cold_ready(clock())
                break


class ReadyPacket:
    """Read only the Port's exact length-prefixed ready message; EOF fails closed."""
    def __init__(self, expected=b'ready', fd=0):
        self.fd = fd
        self.expected = len(expected).to_bytes(4, 'big') + expected
        self.packet = b''

    def __call__(self, timeout):
        readable, _, _ = select.select([self.fd], [], [], timeout)
        if not readable:
            return False
        data = os.read(self.fd, len(self.expected) - len(self.packet))
        self.packet += data
        expected = self.expected
        if not data or not expected.startswith(self.packet):
            raise ValueError('invalid cold readiness packet')
        return self.packet == expected
