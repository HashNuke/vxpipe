"""Contracts for pacing outside the measured BEAM process."""
import json
import unittest
from unittest.mock import patch
from pcm_generator import configure_affinity, generate, wait_until


class PCMGeneratorTest(unittest.TestCase):
    def run_generator(self, *, inputs=2, frames=3, delay=0):
        now = [0]
        packets = []
        def clock():
            return now[0]
        def sleep(seconds):
            now[0] += round(seconds * 1_000_000_000)
        def write(packet):
            packets.append((now[0], packet))
            now[0] += delay
        generate(bytes((index * 7 + index // 256) % 256 for index in range(1280)), inputs, frames, write, clock=clock, sleep=sleep)
        return packets

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
