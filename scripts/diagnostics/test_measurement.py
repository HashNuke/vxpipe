"""Offline contracts for the external diagnostic resource measurement helper."""
import tempfile
import unittest
from pathlib import Path

from measurement import ProcessSample, begin_interval, compare_resources, read_process, summarize


class ResourceMeasurementTest(unittest.TestCase):
    def samples(self, cpu=1.0, rss=100_000):
        return [
            ProcessSample(123, 77, 10.0, 4.0, rss, rss + 100, 14, interval_start=True),
            ProcessSample(123, 77, 30.0, 4.0 + cpu, rss + 1000, rss + 1200, 14),
        ]

    def test_process_cpu_uses_all_process_ticks_and_resident_native_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            process = root / '123'
            process.mkdir()
            # Fields 3..52; the command contains spaces and closing parentheses.
            fields = ['0'] * 50
            fields[0] = 'S'
            fields[11], fields[12], fields[19] = '250', '50', '77'
            (process / 'stat').write_text('123 (beam ) worker) ' + ' '.join(fields))
            (process / 'status').write_text(
                'VmRSS:\t200000 kB\nVmHWM:\t220000 kB\nThreads:\t14\n')
            sample = read_process(123, proc_root=root, ticks_per_second=100, clock=lambda: 10.0)
            self.assertEqual(sample, ProcessSample(123, 77, 10.0, 3.0, 200000, 220000, 14))
            (process / 'clear_refs').touch()
            first = begin_interval(123, proc_root=root, ticks_per_second=100, clock=lambda: 10.0)
            self.assertTrue(first.interval_start)
            self.assertEqual((process / 'clear_refs').read_text(), '5\n')

    def test_cpu_delta_uses_elapsed_interval_and_preserves_high_water(self):
        result = summarize(self.samples(cpu=2.0))
        self.assertEqual(result['cpu_cores'], 0.1)
        self.assertEqual(result['duration_seconds'], 20.0)
        self.assertEqual(result['peak_sampled_rss_kib'], 101000)
        self.assertEqual(result['process_high_water_kib'], 101200)

    def test_missing_or_restarted_process_cannot_produce_a_summary(self):
        for samples in [[], self.samples()[:1], [self.samples()[0],
                ProcessSample(123, 88, 30.0, 5.0, 101000, 101200, 14)]]:
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                summarize(samples)

    def test_unscoped_or_mid_interval_high_water_reset_is_rejected(self):
        samples = self.samples()
        from dataclasses import replace
        for bad in [[replace(samples[0], interval_start=False), samples[1]],
                    [samples[0], replace(samples[1], interval_start=True)]]:
            with self.assertRaises(ValueError):
                summarize(bad)

    def test_invalid_counter_clock_or_nonfinite_sample_fails_closed(self):
        for at, cpu in [(10.0, 5.0), (9.0, 5.0), (30.0, 3.0), (float('nan'), 5.0)]:
            with self.subTest(at=at, cpu=cpu), self.assertRaises(ValueError):
                summarize([self.samples()[0], ProcessSample(123, 77, at, cpu, 101000, 101200, 14)])

    def test_declared_fallback_and_reuse_cpu_budgets_are_distinct(self):
        off = summarize(self.samples(cpu=1.0))
        on = summarize(self.samples(cpu=2.0))  # delta .05 cores
        self.assertTrue(compare_resources(off, on, mode='fallback', inputs=1)['passes'])
        reuse = compare_resources(off, on, mode='reuse', inputs=1)
        self.assertFalse(reuse['passes'])
        self.assertEqual(reuse['cpu_budget_cores'], .025)

    def test_exact_cpu_budget_is_inclusive_without_workload_tolerance(self):
        def summary(cpu_end):
            return summarize([
                ProcessSample(123, 77, 1.0, .1, 100, 100, 1, interval_start=True),
                ProcessSample(123, 77, 21.0, cpu_end, 100, 100, 1),
            ])
        off = summary(4.1)
        self.assertTrue(compare_resources(off, summary(5.7), mode='fallback', inputs=1)['passes'])
        self.assertFalse(compare_resources(off, summary(5.700000001), mode='fallback', inputs=1)['passes'])

    def test_rss_budget_includes_native_high_water_between_samples(self):
        off = summarize(self.samples())
        samples = self.samples()
        samples[-1] = ProcessSample(123, 77, 30.0, 5.0, 101000, 300000, 14)
        on = summarize(samples)
        result = compare_resources(off, on, mode='fallback', inputs=1)
        self.assertFalse(result['passes'])
        self.assertEqual(result['rss_budget_kib'], 136 * 1024)

    def test_invalid_mode_or_capacity_does_not_relax_the_budget(self):
        summary = summarize(self.samples())
        for mode, inputs in [('other', 1), ('reuse', 0), ('fallback', 17), ('reuse', True)]:
            with self.subTest(mode=mode, inputs=inputs), self.assertRaises(ValueError):
                compare_resources(summary, summary, mode=mode, inputs=inputs)


if __name__ == '__main__':
    unittest.main()
