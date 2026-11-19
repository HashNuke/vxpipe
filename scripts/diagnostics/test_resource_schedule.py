"""Resource boundaries must remain tied to the generator's absolute clock."""
from dataclasses import replace
import unittest
from resource_schedule import ResourceSchedule
from measurement import ProcessSample


class ResourceScheduleTest(unittest.TestCase):
    def fixture(self, *, delay_ns=0):
        self.now = 10_000_000_000
        self.resets = []
        def reader(pid):
            self.now += delay_ns
            return ProcessSample(pid, 77, self.now / 1e9, self.now / 2e9,
                                 100, 100, 2)
        def begin(pid, *, expected_start_ticks):
            self.assertEqual(expected_start_ticks, 77)
            self.resets.append(self.now)
            return replace(reader(pid), interval_start=True)
        schedule = ResourceSchedule(123, start_offset_ns=50_000_000, reader=reader, begin=begin, clock=lambda: self.now)
        schedule.start(10_000_000_000, 320_000_000)
        return schedule

    def wait(self, deadline):
        self.now = max(self.now, deadline)

    def test_reset_periodic_samples_and_exact_end_follow_absolute_deadlines(self):
        schedule = self.fixture()
        events = []
        schedule.advance(10_040_000_000, wait=self.wait, emit=events.append)
        self.assertEqual(events, [])
        schedule.advance(10_320_000_000, wait=self.wait, emit=events.append)
        self.assertEqual([e['deadline_ns'] for e in events],
                         [10_050_000_000, 10_150_000_000, 10_250_000_000, 10_320_000_000])
        self.assertEqual(self.resets, [10_050_000_000])
        self.assertEqual([e['sample']['interval_start'] for e in events], [True, False, False, False])
        report = schedule.report()
        self.assertTrue(report['timing_valid'])
        self.assertAlmostEqual(report['summary']['duration_seconds'], .270)
        self.assertAlmostEqual(report['summary']['cpu_cores'], .5)
        self.assertEqual(report['summary']['sample_count'], 4)

    def test_slow_sampling_is_visible_and_does_not_move_future_deadlines(self):
        schedule = self.fixture(delay_ns=3_000_000)
        events = []
        schedule.advance(10_320_000_000, wait=self.wait, emit=events.append)
        report = schedule.report()
        self.assertFalse(report['timing_valid'])
        self.assertEqual(report['start_lateness_ns'], 3_000_000)
        self.assertEqual(report['end_lateness_ns'], 3_000_000)
        self.assertEqual(events[-1]['deadline_ns'], 10_320_000_000)

    def test_interior_jitter_is_reported_but_must_not_skip_the_next_slot(self):
        for delay, expected in [(3_000_000, True), (69_000_000, True), (70_000_000, False)]:
            schedule = self.fixture()
            reader = schedule.reader
            def delayed(pid):
                if self.now == 10_250_000_000:
                    self.now += delay
                    sample = reader(pid)
                    self.now += 1  # read completion follows the counter timestamp
                    return sample
                return reader(pid)
            schedule.reader = delayed
            schedule.advance(10_320_000_000, wait=self.wait, emit=lambda _: None)
            report = schedule.report()
            self.assertEqual(report['timing_contract'], 'boundary-2ms-no-skipped-slot-v1')
            self.assertEqual(report['timing_valid'], expected)
            self.assertEqual(report['maximum_lateness_ns'], delay + 1)
            self.assertEqual(report['start_lateness_ns'], 0)
            self.assertEqual(report['end_lateness_ns'], 0 if expected else 1)

    def test_late_final_read_fails_even_without_any_late_audio(self):
        schedule = self.fixture()
        reader = schedule.reader
        def delayed(pid):
            if self.now == 10_320_000_000:
                self.now += 500_000_000
            return reader(pid)
        schedule.reader = delayed
        schedule.advance(10_320_000_000, wait=self.wait, emit=lambda _: None)
        self.assertFalse(schedule.report()['timing_valid'])
        self.assertEqual(schedule.report()['end_lateness_ns'], 500_000_000)

    def test_end_coincident_with_periodic_deadline_is_sampled_once(self):
        now = [0]
        def read(pid):
            return ProcessSample(pid, 77, now[0] / 1e9, 0, 100, 100, 1)
        schedule = ResourceSchedule(123, reader=read,
            begin=lambda pid, **_: replace(read(pid), interval_start=True), clock=lambda: now[0])
        schedule.start(0, 200_000_000)
        events = []
        schedule.advance(200_000_000, wait=lambda deadline: now.__setitem__(0, deadline), emit=events.append)
        self.assertEqual([e['deadline_ns'] for e in events], [0, 100_000_000, 200_000_000])
        self.assertTrue(schedule.report()['timing_valid'])

    def test_no_summary_before_end_and_no_reuse_after_end(self):
        schedule = self.fixture()
        with self.assertRaises(ValueError):
            schedule.report()
        schedule.advance(10_320_000_000, wait=self.wait, emit=lambda _: None)
        with self.assertRaises(ValueError):
            schedule.start(20_000_000_000, 320_000_000)

    def test_replaced_target_is_rejected_before_reset(self):
        schedule = self.fixture()
        def replaced(_pid, *, expected_start_ticks):
            raise ValueError('process replaced before interval reset')
        schedule.begin = replaced
        with self.assertRaises(ValueError):
            schedule.advance(10_100_000_000, wait=self.wait, emit=lambda _: None)
        self.assertEqual(self.resets, [])

    def test_invalid_interval_cannot_start(self):
        for offset, duration in [(-1, 100), (100, 100), (True, 100), (0, 32_000_000_001)]:
            with self.subTest(offset=offset, duration=duration), self.assertRaises(ValueError):
                schedule = ResourceSchedule(123, start_offset_ns=offset,
                    reader=lambda pid: ProcessSample(pid, 77, 10, 1, 100, 100, 1))
                schedule.start(10_000_000_000, duration)


if __name__ == '__main__':
    unittest.main()
