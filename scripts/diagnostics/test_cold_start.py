"""Cold handshake must retain initialization cost without pacing audio on responses."""
from dataclasses import replace
import json
import os
import unittest
from measurement import ProcessSample
from resource_schedule import ResourceSchedule
from cold_start import prepare, ReadyPacket
from pcm_generator import generate


class ColdStartTest(unittest.TestCase):
    def fixture(self, ready_at):
        self.now = 0
        self.packets = []
        def read(pid):
            return ProcessSample(pid, 77, self.now / 1e9, self.now / 2e9, 100, 100, 2)
        resources = ResourceSchedule(123, reader=read,
            begin=lambda pid, **_: replace(read(pid), interval_start=True), clock=lambda: self.now)
        def ready(timeout):
            self.now = min(self.now + round(timeout * 1e9), ready_at)
            return self.now >= ready_at
        return resources, ready

    def test_resource_reset_and_sampling_include_preparation_and_fixed_audio(self):
        resources, ready = self.fixture(2_050_000_000)
        prepare(resources, self.packets.append, ready, clock=lambda: self.now)
        self.assertEqual(self.now, 2_050_000_000)
        first = json.loads(self.packets[0][1:])
        self.assertTrue(first['sample']['interval_start'])
        generate(bytes(1024), 1, 625, self.packets.append, resources=resources, workload='cold',
                 settlement_inputs_per_room=1, clock=lambda: self.now,
                 sleep=lambda seconds: setattr(self, 'now', self.now + round(seconds * 1e9)))
        result = json.loads(self.packets[-1][1:])
        self.assertEqual(result['frames_sent'], 625)
        self.assertEqual(result['elapsed_ns'], 20_000_000_000)
        self.assertAlmostEqual(result['resource_interval']['summary']['duration_seconds'], 22.05)
        self.assertEqual(result['resource_interval']['preparation_duration_ns'], 2_050_000_000)
        self.assertAlmostEqual(result['resource_interval']['preparation_cpu_seconds'], 1.025)
        self.assertEqual(sum(json.loads(p[1:])['sample']['interval_start'] for p in self.packets if p[0] == 3), 1)

    def test_manifest_work_and_trace_start_delay_are_not_stt_readiness(self):
        resources, ready = self.fixture(2_000_000_000)
        def start_ready(timeout):
            self.now = min(self.now + round(timeout * 1e9), 2_500_000_000)
            return self.now >= 2_500_000_000
        prepare(resources, self.packets.append, ready, start_ready=start_ready, clock=lambda: self.now)
        # Static manifest work after readiness may delay audio, but not readiness.
        def write(packet):
            self.packets.append(packet)
            if packet[0] == 0:
                self.now += 1_000_000
        generate(bytes(1024), 1, 625, write, resources=resources, workload='cold',
                 settlement_inputs_per_room=1, clock=lambda: self.now,
                 sleep=lambda seconds: setattr(self, 'now', self.now + round(seconds * 1e9)))
        interval = json.loads(self.packets[-1][1:])['resource_interval']
        self.assertEqual(interval['preparation_duration_ns'], 2_000_000_000)
        self.assertEqual(interval['audio_start_ns'], 2_501_000_000)
        self.assertEqual(interval['summary']['duration_seconds'], 22.501)

    def test_static_manifest_is_complete_before_reset(self):
        resources, ready = self.fixture(2_000_000_000)
        def write(packet):
            self.packets.append(packet)
            if packet[0] == 0:
                self.now += 1_000_000_000
        generate(bytes(1024), 1, 625, write, resources=resources, workload='cold',
                 preparation=lambda: prepare(resources, write, ready, clock=lambda: self.now),
                 settlement_inputs_per_room=1, clock=lambda: self.now,
                 sleep=lambda seconds: setattr(self, 'now', self.now + round(seconds * 1e9)))
        self.assertEqual(self.packets[0][0], 0)
        first = json.loads(self.packets[1][1:])
        self.assertEqual(first['deadline_ns'], 1_000_000_000)
        interval = json.loads(self.packets[-1][1:])['resource_interval']
        self.assertEqual(interval['preparation_duration_ns'], 1_000_000_000)
        self.assertEqual(interval['summary']['duration_seconds'], 21)

    def test_adjacent_ready_and_start_packets_remain_distinct(self):
        read, write = os.pipe()
        try:
            os.write(write, b'\0\0\0\5ready\0\0\0\5start')
            self.assertTrue(ReadyPacket(fd=read)(0))
            self.assertTrue(ReadyPacket(b'start', fd=read)(0))
        finally:
            os.close(read)
            os.close(write)

    def test_post_ready_trace_setup_does_not_consume_stt_deadline(self):
        resources, ready = self.fixture(14_999_000_000)
        def start_ready(timeout):
            self.now = min(self.now + round(timeout * 1e9), 15_001_000_000)
            return self.now >= 15_001_000_000
        prepare(resources, self.packets.append, ready, start_ready=start_ready, clock=lambda: self.now)
        resources.cold_audio_start(self.now)
        self.assertEqual(resources.preparation['preparation_duration_ns'], 14_999_000_000)
        self.assertEqual(resources.audio_start_ns, 15_001_000_000)

    def test_crossing_a_periodic_sample_slot_is_not_a_readiness_timeout(self):
        resources, ready = self.fixture(2_000_000_000)
        calls = [0]
        def clock():
            calls[0] += 1
            if calls[0] == 3:
                self.now = 100_000_001
            return self.now
        prepare(resources, self.packets.append, ready, clock=clock)
        self.assertEqual(resources.preparation['preparation_duration_ns'], 2_000_000_000)

    def test_late_trace_start_keeps_sampling_until_audio_is_released(self):
        resources, ready = self.fixture(1_000_000_000)
        calls = [0]
        def clock():
            calls[0] += 1
            self.assertLess(calls[0], 5000, 'sampler spun after closing before audio start')
            return self.now
        def start_ready(timeout):
            self.now = min(self.now + round(timeout * 1e9), 22_000_000_000)
            return self.now >= 22_000_000_000
        prepare(resources, self.packets.append, ready, start_ready=start_ready, clock=clock)
        self.assertEqual(self.now, 22_000_000_000)
        self.assertFalse(resources.closed)
        resources.cold_audio_start(self.now)
        self.assertEqual(resources.end_ns, 42_000_000_000)

    def test_no_readiness_after_fifteen_seconds(self):
        resources, ready = self.fixture(15_000_000_001)
        with self.assertRaises(ValueError):
            prepare(resources, self.packets.append, ready, clock=lambda: self.now)
        self.assertLessEqual(self.now, 15_000_000_000)
        self.assertFalse(any(p[0] == 1 for p in self.packets))


if __name__ == '__main__':
    unittest.main()
