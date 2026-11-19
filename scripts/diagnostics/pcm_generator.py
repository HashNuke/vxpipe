"""Bounded external PCM pacing; stdout is a four-byte-length packet protocol.

Packet 0: JSON manifest. Packet 1: uint16 input, uint32 sequence, 1024 PCM bytes.
Packet 2: JSON timing report. No downstream acknowledgement changes the schedule.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys
import time

PERIOD_NS = 32_000_000


def generate(pcm, inputs, frames, write, *, clock=time.monotonic_ns, sleep=time.sleep, affinity=None,
             spin_ns=0, settlement_inputs_per_room=None):
    if (type(inputs) is not int or not 1 <= inputs <= 16
            or type(frames) is not int or not 1 <= frames <= 1000
            or len(pcm) < 1024 or len(pcm) % 2
            or type(spin_ns) is not int or not 0 <= spin_ns <= 2_000_000):
        raise ValueError('invalid bounded 16 kHz PCM workload')
    settlements = None
    speech_clip = (pcm * math.ceil(32768 / len(pcm)))[:32768]
    if settlement_inputs_per_room is not None:
        if (type(settlement_inputs_per_room) is not int or settlement_inputs_per_room not in (1, 2)
                or inputs % settlement_inputs_per_room or frames < 128):
            raise ValueError('invalid settlement topology or duration')
        rooms = inputs // settlement_inputs_per_room
        settlements = []
        for index in range(inputs):
            slot = (index % settlement_inputs_per_room) * rooms + index // settlement_inputs_per_room
            first = 64 + 64 * (slot + 1) // inputs
            settlements.append(list(range(first, frames + 1, 64)))
    manifest = dict(inputs=inputs, frames_per_input=frames, sample_rate=16000,
                    samples_per_frame=512, fixture_sha256=hashlib.sha256(pcm).hexdigest(),
                    generator_cpu_affinity=affinity, pacing_spin_ns=spin_ns,
                    input_encoding='first-sample-index' if inputs > 1 else 'fixture',
                    provider_settlement_frames=settlements,
                    speech_clip=dict(offset_samples=0, samples=16384, sha256=hashlib.sha256(speech_clip).hexdigest()) if settlements else None,
                    tail_encoding='silence-outside-speech-windows' if settlements else 'fixture')
    write(b'\0' + json.dumps(manifest).encode())
    start = clock()
    cpu_start = time.process_time()
    lateness = []
    wake_lateness = []
    write_durations = []
    for sequence in range(frames):
        offset = sequence * 1024 % len(pcm)
        chunk = pcm[offset:offset + 1024]
        chunk += pcm[:1024 - len(chunk)]
        for index in range(inputs):
            deadline = start + sequence * PERIOD_NS + PERIOD_NS * index // inputs
            wait_until(deadline, clock=clock, sleep=sleep, spin_ns=spin_ns)
            before_write = clock()
            # Distinguish sources without changing frame size or pacing. These
            # workload fixtures are not acoustic-accuracy ground truth.
            source_pcm = chunk
            if settlements:
                ending = next((end for end in settlements[index] if end - 31 <= sequence + 1 <= end), None)
                if ending is None:
                    source_pcm = bytes(1024)
                else:
                    speech_offset = (sequence + 1 - (ending - 31)) * 1024
                    source_pcm = speech_clip[speech_offset:speech_offset + 1024]
            payload = struct.pack('<h', index + 1) + source_pcm[2:] if inputs > 1 else source_pcm
            write(b'\1' + struct.pack('>HI', index, sequence) + payload)
            after_write = clock()
            wake_lateness.append(max(0, before_write - deadline))
            write_durations.append(after_write - before_write)
            # Include pipe backpressure, not just the time before attempting write.
            lateness.append(max(0, after_write - deadline))
    wait_until(start + frames * PERIOD_NS, clock=clock, sleep=sleep, spin_ns=spin_ns)
    p95 = sorted(lateness)[math.ceil(len(lateness) * .95) - 1]
    report = dict(frames_sent=len(lateness), lateness_ns=lateness, p95_lateness_ns=p95,
                  wake_lateness_ns=wake_lateness, write_duration_ns=write_durations,
                  elapsed_ns=clock() - start, generator_cpu_seconds=time.process_time() - cpu_start,
                  timing_valid=p95 <= 2_000_000)
    write(b'\2' + json.dumps(report).encode())


def wait_until(deadline, *, clock, sleep, spin_ns):
    remaining = deadline - clock()
    while remaining > 0:
        if remaining > spin_ns:
            sleep((remaining - spin_ns) / 1_000_000_000)
        remaining = deadline - clock()


def configure_affinity(value):
    if value is not None:
        cpus = [int(part) for part in value.split(',')]
        if not cpus or any(cpu < 0 for cpu in cpus) or len(set(cpus)) != len(cpus):
            raise ValueError('invalid generator CPU affinity')
        os.sched_setaffinity(0, set(cpus))
    actual = sorted(os.sched_getaffinity(0))
    if value is not None and actual != sorted(cpus):
        raise ValueError("generator CPU affinity was not applied exactly")
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pcm', required=True, type=Path)
    parser.add_argument('--inputs', required=True, type=int)
    parser.add_argument('--frames', required=True, type=int)
    parser.add_argument('--spin-us', type=int, default=2000, help='bounded final spin guard (0..2000 us)')
    parser.add_argument('--cpus', help='explicit external-generator CPU ids, e.g. 2,3')
    parser.add_argument('--settlement-inputs-per-room', type=int, choices=(1, 2),
                        help='declare fixed 32-frame speech windows ending at provider settlements')
    args = parser.parse_args()
    affinity = configure_affinity(args.cpus)
    def write(packet):
        sys.stdout.buffer.write(struct.pack('>I', len(packet)) + packet)
        sys.stdout.buffer.flush()
    generate(args.pcm.read_bytes(), args.inputs, args.frames, write, affinity=affinity,
             spin_ns=args.spin_us * 1000, settlement_inputs_per_room=args.settlement_inputs_per_room)


if __name__ == '__main__':
    main()
