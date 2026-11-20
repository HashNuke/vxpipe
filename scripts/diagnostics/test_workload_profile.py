"""Declared workload windows, independent of model/response readiness."""
import unittest
from workload_profile import profile


class WorkloadProfileTest(unittest.TestCase):
    def test_smoke_retains_existing_frames_turns_and_duration(self):
        smoke = profile('smoke')
        self.assertEqual(smoke.duration_ns, 6_144_000_000)
        self.assertEqual(smoke.measurement_start_ns, 0)
        self.assertEqual(smoke.maximum_frames, 192)
        self.assertEqual(smoke.settlements(0, 1, 1), [128, 192])
        self.assertEqual(smoke.speech_frames, 32)

    def test_every_warm_input_has_exactly_625_measured_frames_and_at_least_ten_turns(self):
        warm = profile('warm')
        self.assertEqual((warm.measurement_start_ns, warm.duration_ns), (5_000_000_000, 25_000_000_000))
        self.assertEqual(warm.maximum_frames, 782)
        for humans in (1, 2):
            for rooms in range(1, 16 // humans + 1):
                inputs = rooms * humans
                for index in range(inputs):
                    deadlines = [sequence * 32_000_000 + 32_000_000 * index // inputs
                                 for sequence in range(warm.maximum_frames)]
                    offered = [at for at in deadlines if at < 25_000_000_000]
                    self.assertEqual(warm.frame_count(index, inputs), len(offered))
                    self.assertEqual(sum(5_000_000_000 <= at < 25_000_000_000 for at in offered), 625)
                    ends = warm.settlements(index, inputs, humans)
                    self.assertGreaterEqual(sum(5_000_000_000 <= deadlines[end - 1] < 25_000_000_000
                                                for end in ends), 10)
                    self.assertEqual(len(ends), len(set(ends)))
                    self.assertLessEqual(ends[-1], len(offered))
                if humans == 2:
                    for room in range(rooms):
                        first = warm.settlements(room * 2, inputs, humans)
                        second = warm.settlements(room * 2 + 1, inputs, humans)
                        for a, b in zip(first, second):
                            self.assertEqual(b - a, 30)
                            self.assertEqual((b - warm.speech_frames + 1) - a - 1, 6)

    def test_cold_audio_is_twenty_seconds_with_ten_turns_per_input(self):
        cold = profile('cold')
        self.assertEqual((cold.measurement_start_ns, cold.duration_ns), (0, 20_000_000_000))
        for rooms, humans in [(1, 1), (8, 2)]:
            for index in range(rooms * humans):
                self.assertEqual(cold.frame_count(index, rooms * humans), 625)
                self.assertGreaterEqual(len(cold.settlements(index, rooms * humans, humans)), 10)
                self.assertGreaterEqual(cold.settlements(index, rooms * humans, humans)[0], cold.speech_frames)

    def test_bad_profile_or_source_shape_cannot_be_used(self):
        with self.assertRaises(ValueError):
            profile('unknown')
        for index, inputs, humans in [(0, 0, 1), (16, 16, 1), (0, 3, 2), (0, 17, 1)]:
            with self.subTest(index=index, inputs=inputs), self.assertRaises(ValueError):
                profile('warm').settlements(index, inputs, humans)


if __name__ == '__main__':
    unittest.main()
