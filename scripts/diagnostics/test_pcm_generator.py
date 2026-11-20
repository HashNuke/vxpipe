"""Contracts for pacing outside the measured BEAM process."""
import hashlib
import json
import unittest
from unittest.mock import patch
from dataclasses import replace
from measurement import ProcessSample
from resource_schedule import ResourceSchedule
from pcm_generator import configure_affinity, generate, wait_until


class PCMGeneratorTest(unittest.TestCase):
    def run_generator(self, *, inputs=2, frames=3, delay=0, settlement_inputs_per_room=None):
        now = [0]
        packets = []
        def clock():
            return now[0]
        def sleep(seconds):
            now[0] += round(seconds * 1_000_000_000)
        def write(packet):
            packets.append((now[0], packet))
            now[0] += delay
        generate(bytes((index * 7 + index // 256) % 256 for index in range(1280)), inputs, frames, write, clock=clock, sleep=sleep,
                 settlement_inputs_per_room=settlement_inputs_per_room)
        return packets

    def test_resource_sampling_retains_audio_deadlines_and_streams_raw_samples(self):
        for delay in (0, 40_000_000):
            now = [0]
            packets = []
            def reader(pid):
                return ProcessSample(pid, 77, now[0] / 1e9, now[0] / 2e9, 100, 100, 2)
            def begin(pid, *, expected_start_ticks):
                self.assertEqual(expected_start_ticks, 77)
                now[0] += delay
                return replace(reader(pid), interval_start=True)
            resources = ResourceSchedule(123, start_offset_ns=50_000_000, reader=reader, begin=begin, clock=lambda: now[0])
            generate(bytes(1024), 1, 6, lambda p: packets.append((now[0], p)),
                     clock=lambda: now[0], sleep=lambda seconds: now.__setitem__(0, now[0] + round(seconds * 1e9)),
                     resources=resources)
            samples = [json.loads(p[1:]) for _, p in packets if p[0] == 3]
            self.assertEqual([s['deadline_ns'] for s in samples], [50_000_000, 150_000_000, 192_000_000])
            audio = [(at, p) for at, p in packets if p[0] == 1]
            self.assertEqual(len(audio), 6)
            self.assertEqual([int.from_bytes(p[3:7], 'big') for _, p in audio], list(range(6)))
            report = json.loads(packets[-1][1][1:])
            self.assertEqual(report['resource_interval']['summary']['sample_count'], 3)
            self.assertEqual(report['resource_interval']['timing_valid'], delay == 0)
            self.assertEqual(audio[-1][0], 160_000_000)
            self.assertEqual(report['lateness_ns'][2], 26_000_000 if delay else 0)

    def test_warm_profile_emits_only_inside_25_seconds_and_measures_exactly_twenty(self):
        now = [0]
        packets = []
        def read(pid):
            return ProcessSample(pid, 77, now[0] / 1e9, now[0] / 2e9, 100, 100, 2)
        resources = ResourceSchedule(123, start_offset_ns=5_000_000_000, reader=read,
            begin=lambda pid, **_: replace(read(pid), interval_start=True), clock=lambda: now[0])
        generate(b'\x10\x00' * 512, 4, 782, lambda p: packets.append((now[0], p)),
                 clock=lambda: now[0], sleep=lambda seconds: now.__setitem__(0, now[0] + round(seconds * 1e9)),
                 settlement_inputs_per_room=2, resources=resources, workload='warm')
        manifest = json.loads(packets[0][1][1:])
        self.assertEqual(manifest['workload_profile'], 'warm')
        self.assertEqual(manifest['input_frame_counts'], [782, 781, 781, 781])
        self.assertEqual(manifest['speech_clip']['samples'], 24 * 512)
        audio = [(at, p) for at, p in packets if p[0] == 1]
        self.assertEqual(len(audio), 3125)
        self.assertTrue(all(at < 25_000_000_000 for at, _ in audio))
        for index in range(4):
            own = [(at, p) for at, p in audio if int.from_bytes(p[1:3], 'big') == index]
            self.assertEqual(len(own), manifest['input_frame_counts'][index])
            self.assertEqual(sum(at >= 5_000_000_000 for at, _ in own), 625)
            self.assertEqual([int.from_bytes(p[3:7], 'big') for _, p in own], list(range(len(own))))
        resources = [json.loads(p[1:]) for _, p in packets if p[0] == 3]
        self.assertEqual([s['deadline_ns'] for s in resources], list(range(5_000_000_000, 25_000_000_001, 100_000_000)))
        report = json.loads(packets[-1][1][1:])
        self.assertEqual(report['elapsed_ns'], 25_000_000_000)
        self.assertEqual(report['resource_interval']['summary']['duration_seconds'], 20)
        self.assertEqual(report['frames_sent'], 3125)
        self.assertEqual(report['measured_frames_sent'], 2500)
        self.assertEqual(report['audio_start_ns'], 0)

    def test_warm_payload_matches_independent_speech_windows_for_every_shape(self):
        fixture = bytes((index * 7 + index // 256) % 256 for index in range(1280))
        clip = (fixture * 20)[:24 * 1024]
        for humans in (1, 2):
            for rooms in range(1, 16 // humans + 1):
                inputs = rooms * humans
                now = [0]
                packets = []
                generate(fixture, inputs, 782, packets.append, clock=lambda: now[0],
                         sleep=lambda seconds: now.__setitem__(0, now[0] + round(seconds * 1e9)),
                         settlement_inputs_per_room=humans, workload='warm')
                expected_ends = [list(range(64 + 60 * ((i % humans) * rooms + i // humans + 1) // inputs,
                                            783 if i == 0 or 32_000_000 * i // inputs < 8_000_000 else 782, 60))
                                 for i in range(inputs)]
                manifest = json.loads(packets[0][1:])
                self.assertEqual(manifest['provider_settlement_frames'], expected_ends)
                for packet in packets:
                    if packet[0] != 1:
                        continue
                    index = int.from_bytes(packet[1:3], 'big')
                    frame = int.from_bytes(packet[3:7], 'big') + 1
                    end = next((end for end in expected_ends[index] if end - 23 <= frame <= end), None)
                    offset = None if end is None else (frame - end + 23) * 1024
                    raw = bytes(1024) if offset is None else clip[offset:offset + 1024]
                    expected = (index + 1).to_bytes(2, 'little') + raw[2:] if inputs > 1 else raw
                    self.assertEqual(packet[7:], expected, (rooms, humans, index, frame))
                if humans == 2:
                    for room in range(rooms):
                        for first in expected_ends[2 * room]:
                            for second in expected_ends[2 * room + 1]:
                                self.assertGreaterEqual(abs(first - second), 24)

    def test_warmup_cannot_dilute_measured_audio_lateness(self):
        now = [0]
        packets = []
        def write(packet):
            packets.append(packet)
            if packet[0] == 1 and 157 <= int.from_bytes(packet[3:7], 'big') < 192:
                now[0] += 3_000_000
        generate(bytes(1024), 1, 782, write, clock=lambda: now[0],
                 sleep=lambda seconds: now.__setitem__(0, now[0] + round(seconds * 1e9)),
                 settlement_inputs_per_room=1, workload='warm')
        report = json.loads(packets[-1][1:])
        self.assertEqual(report['p95_lateness_ns'], 0)
        self.assertFalse(report['timing_valid'])
        self.assertEqual(report['measured_p95_lateness_ns'], 3_000_000)
        self.assertEqual(len(report['measured_lateness_ns']), 625)

    def test_staggered_absolute_schedule_keeps_each_stream_at_32ms(self):
        packets = self.run_generator()
        audio = [(at, packet) for at, packet in packets if packet[0] == 1]
        self.assertEqual([at for at, _ in audio], [0, 16_000_000, 32_000_000, 48_000_000, 64_000_000, 80_000_000])
        self.assertEqual([int.from_bytes(p[1:3], 'big') for _, p in audio], [0, 1, 0, 1, 0, 1])
        self.assertEqual([int.from_bytes(p[3:7], 'big') for _, p in audio], [0, 0, 1, 1, 2, 2])
        self.assertTrue(all(len(p[7:]) == 1024 for _, p in audio))
        self.assertEqual(packets[-1][0], 96_000_000)

    def test_concurrent_inputs_have_distinct_audio_for_cross_source_checks(self):
        packets = self.run_generator(inputs=2, frames=3)
        audio = [packet for _, packet in packets if packet[0] == 1]
        for sequence in range(3):
            first, second = audio[2 * sequence:2 * sequence + 2]
            self.assertEqual(first[7:9], b'\x01\x00')
            self.assertEqual(second[7:9], b'\x02\x00')
            self.assertEqual(first[9:], second[9:])
            self.assertNotEqual(first[7:], second[7:])
        self.assertEqual(json.loads(packets[0][1][1:])['input_encoding'], 'first-sample-index')

    def test_conversation_windows_preserve_pcm_without_same_room_speech_overlap(self):
        fixture = bytes((index * 7 + index // 256) % 256 for index in range(1280))
        for humans in (1, 2):
            for rooms in range(1, 16 // humans + 1):
                inputs = rooms * humans
                packets = self.run_generator(inputs=inputs, frames=192, settlement_inputs_per_room=humans)
                manifest = json.loads(packets[0][1][1:])
                expected = [[64 + 64 * ((index % humans) * rooms + index // humans + 1) // inputs + turn * 64
                             for turn in range(2)] for index in range(inputs)]
                self.assertEqual(manifest['provider_settlement_frames'], expected)
                self.assertEqual(manifest['tail_encoding'], 'silence-outside-speech-windows')
                self.assertEqual(manifest['speech_clip'], dict(offset_samples=0, samples=16384, sha256=hashlib.sha256((fixture * 26)[:32768]).hexdigest()))
                audio = {(int.from_bytes(p[1:3], 'big'), int.from_bytes(p[3:7], 'big')): (at, p[7:])
                         for at, p in packets if p[0] == 1}
                self.assertEqual(len(audio), 192 * inputs)
                for sequence in range(192):
                    for index in range(inputs):
                        frame = sequence + 1
                        ending = next((end for end in expected[index] if end - 31 <= frame <= end), None)
                        offset = (frame - (ending - 31)) * 1024 if ending is not None else None
                        raw = bytes(1024) if offset is None else bytes(fixture[(offset + i) % len(fixture)] for i in range(1024))
                        payload = (index + 1).to_bytes(2, 'little') + raw[2:] if inputs > 1 else raw
                        self.assertEqual(audio[index, sequence], (sequence * 32_000_000 + 32_000_000 * index // inputs, payload))
                    if humans == 2:
                        for room in range(rooms):
                            active = [any(end - 31 <= sequence + 1 <= end for end in expected[index])
                                      for index in (room * 2, room * 2 + 1)]
                            self.assertLessEqual(sum(active), 1)
                self.assertGreaterEqual(min(ends[0] - 31 for ends in expected), 37)
                self.assertEqual(json.loads(packets[-1][1][1:])['frames_sent'], 192 * inputs)

    def test_settlement_profile_rejects_incomplete_or_unbounded_shapes(self):
        for inputs, frames, humans in [(1, 64, 2), (3, 64, 2), (2, 127, 2), (2, 64, True)]:
            with self.subTest(inputs=inputs, frames=frames, humans=humans), self.assertRaises(ValueError):
                generate(bytes(1024), inputs, frames, lambda _: None,
                         settlement_inputs_per_room=humans)

    def test_blocked_write_lateness_is_reported_without_shifting_deadlines(self):
        packets = self.run_generator(inputs=1, frames=3, delay=40_000_000)
        report = json.loads(packets[-1][1][1:])
        self.assertEqual(report['lateness_ns'], [40_000_000, 48_000_000, 56_000_000])
        self.assertEqual(report['frames_sent'], 3)
        self.assertEqual(report['wake_lateness_ns'], [0, 8_000_000, 16_000_000])
        self.assertEqual(report['write_duration_ns'], [40_000_000] * 3)
        self.assertFalse(report['timing_valid'])

    def test_repeated_pcm_wraps_without_losing_or_padding_samples(self):
        packets = self.run_generator(inputs=1, frames=3)
        audio = b''.join(p[7:] for _, p in packets if p[0] == 1)
        fixture = bytes((index * 7 + index // 256) % 256 for index in range(1280))
        self.assertEqual(audio, (fixture * 3)[:3072])
        report = json.loads(packets[-1][1][1:])
        self.assertTrue(report['timing_valid'])
        self.assertEqual(report['lateness_ns'], [0, 0, 0])

    def test_bounded_spin_guard_absorbs_sleep_overshoot(self):
        now = [0]
        sleeps = []
        def clock():
            now[0] += 10_000
            return now[0]
        def sleep(seconds):
            sleeps.append(seconds)
            now[0] += round(seconds * 1_000_000_000) + 1_000_000
        wait_until(32_000_000, clock=clock, sleep=sleep, spin_ns=2_000_000)
        self.assertLessEqual(now[0] - 32_000_000, 10_000)
        self.assertEqual(len(sleeps), 1)
        self.assertLess(sleeps[0], .030)

    def test_external_generator_affinity_is_explicit_and_reported(self):
        with patch('pcm_generator.os.sched_setaffinity') as setter, patch(
                'pcm_generator.os.sched_getaffinity', return_value={2, 3}):
            self.assertEqual(configure_affinity('2,3'), [2, 3])
            setter.assert_called_once_with(0, {2, 3})

    def test_invalid_or_unavailable_affinity_is_not_silently_ignored(self):
        for value in ['', '0,-1', 'a', '1,1']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                configure_affinity(value)
        with patch('pcm_generator.os.sched_setaffinity'), patch(
                'pcm_generator.os.sched_getaffinity', return_value={2}):
            with self.assertRaises(ValueError):
                configure_affinity('2,3')
        with patch('pcm_generator.os.sched_setaffinity', side_effect=OSError('unavailable')):
            with self.assertRaises(OSError):
                configure_affinity('2,3')

    def test_invalid_workload_cannot_start_output(self):
        for pcm, inputs, frames in [(b'\0', 1, 3), (b'\0' * 1024, 0, 3),
                                    (b'\0' * 1024, 17, 3), (b'\0' * 1024, 1, 1001)]:
            with self.subTest(inputs=inputs, frames=frames), self.assertRaises(ValueError):
                generate(pcm, inputs, frames, lambda _: self.fail('unexpected output'))


if __name__ == '__main__':
    unittest.main()
