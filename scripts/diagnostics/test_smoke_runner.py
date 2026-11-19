"""Watchdog authority and invalid-run contracts, without privileged processes."""
import json
import unittest
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch
from smoke_runner import OwnedUnits, violation, parse_cpu_mask, smoke_complete, watch, stop_unit

RUN = '1234567890abcdef1234567890abcdef'
LEAF = '12345678-1234-1234-1234-123456789abc'


def reports():
    return [dict(operational_vad=vad, collection=enabled,
                 generator=dict(frames_sent=64, p95_lateness_ns=1000,
                                elapsed_ns=2_048_000_000))
            for vad in (False, True) for enabled in (False, True)]


def sample(pid, start):
    return dict(available_kib=2_000_000,
                beams=[dict(pid=pid, start_ticks=start, rss_kib=100_000,
                            thread_cpu_masks=['0-1'])])


class SmokeRunnerTest(unittest.TestCase):
    def test_only_this_run_can_register_cleanup_units(self):
        owned = OwnedUnits(RUN)
        name = f'vxpipe-diagnostic-generator-{RUN}-{LEAF}.service'
        owned.observe('.DIAGNOSTIC_GENERATOR_UNIT ' + name + '\n')
        owned.observe('DIAGNOSTIC_GENERATOR_UNIT ' + name)
        self.assertEqual(owned.generators, {name})
        self.assertEqual(owned.scope, f'vxpipe-diagnostic-smoke-{RUN}.scope')
        for other in ['vxpipe.service', f'vxpipe-diagnostic-generator-{LEAF}.service',
                      name + ' extra', name.replace(RUN, 'a' * 32)]:
            with self.subTest(other=other), self.assertRaises(ValueError):
                owned.observe('DIAGNOSTIC_GENERATOR_UNIT ' + other)
        self.assertEqual(owned.generators, {name})

    def test_cleanup_stops_only_registered_user_units_and_owned_system_scope(self):
        owned = OwnedUnits(RUN)
        name = f'vxpipe-diagnostic-generator-{RUN}-{LEAF}.service'
        owned.observe('DIAGNOSTIC_GENERATOR_UNIT ' + name)
        with patch('smoke_runner.subprocess.run', return_value=Mock(returncode=0)) as run:
            stop_unit(owned.scope, system=True)
            stop_unit(name)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands, [
            ['sudo', '-n', 'systemctl', 'stop', owned.scope],
            ['systemctl', '--user', 'stop', name]])

    def test_aborted_database_creation_remains_identified_until_drop_is_acknowledged(self):
        owned = OwnedUnits(RUN)
        database = f'vxdiag_{RUN}_12345678'
        owned.observe('DIAGNOSTIC_DATABASE_RESERVED ' + database)
        self.assertEqual(owned.pending_databases, {database})
        for other in ['vxpipe_test', database.replace(RUN, 'a' * 32)]:
            with self.assertRaises(ValueError):
                owned.observe('DIAGNOSTIC_DATABASE_RESERVED ' + other)
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'workload.log'
            log.write_text(''.join('DIAGNOSTIC_EXTERNAL_SMOKE ' + json.dumps(r) + '\n'
                                   for r in reports()))
            process = Mock(pid=123, returncode=0)
            process.poll.side_effect = [None, 0]
            with patch('smoke_runner.stop_unit'):
                result = watch(process, owned, log, sample=lambda _: sample(900, 10),
                               sleep=lambda _: None)
            self.assertFalse(result['completed'])
            self.assertEqual(result['retained_databases'], [database])
        owned.observe('DIAGNOSTIC_DATABASE_DROPPED ' + database)
        self.assertEqual(owned.pending_databases, set())
        with self.assertRaises(ValueError):
            owned.observe('DIAGNOSTIC_DATABASE_DROPPED ' + database)

    def test_watchdog_never_accepts_memory_cpu_escape_or_timeout(self):
        good = dict(rss_kib=100_000, thread_cpu_masks=['0-1', '1'])
        self.assertIsNone(violation([good], available_kib=800_000, elapsed=20))
        for beams, available, elapsed in [
                ([dict(good, rss_kib=1024 * 1024 + 1)], 800_000, 20),
                ([good], 768 * 1024 - 1, 20),
                ([dict(good, thread_cpu_masks=['0-1', '2'])], 800_000, 20),
                ([good], 800_000, 301)]:
            with self.subTest(beams=beams, available=available, elapsed=elapsed):
                self.assertIsNotNone(violation(beams, available_kib=available, elapsed=elapsed))

    def test_aggregate_vm_rss_counts_every_observed_vm(self):
        beam = dict(rss_kib=600_000, thread_cpu_masks=['0-1'])
        self.assertIsNotNone(violation([beam, beam], available_kib=900_000, elapsed=20))

    def test_empty_or_invalid_native_masks_are_not_valid_measurements(self):
        for mask in ['', '1-0', 'x', '0-999999']:
            with self.subTest(mask=mask), self.assertRaises(ValueError):
                parse_cpu_mask(mask)
        self.assertEqual(parse_cpu_mask('0-1,3'), {0, 1, 3})
        self.assertIsNotNone(violation([dict(rss_kib=1, thread_cpu_masks=[])],
                                       available_kib=900_000, elapsed=20))

    def test_zero_exit_without_complete_matrix_or_resource_samples_is_not_success(self):
        reports = [dict(operational_vad=vad, collection=enabled,
                        generator=dict(frames_sent=64, p95_lateness_ns=1000, elapsed_ns=2_048_000_000))
                   for vad in (False, True) for enabled in (False, True)]
        samples = [dict(beams=[dict(rss_kib=100)])]
        self.assertTrue(smoke_complete(reports, samples))
        self.assertFalse(smoke_complete(reports[:-1], samples))
        self.assertFalse(smoke_complete(reports, []))
        self.assertFalse(smoke_complete(reports[:-1] + [reports[0]], samples))
        reports[0]['generator']['elapsed_ns'] = 0
        self.assertFalse(smoke_complete(reports, samples))
        reports[0]['generator']['elapsed_ns'] = 2_048_000_000
        reports[0]['generator']['p95_lateness_ns'] = -1
        self.assertFalse(smoke_complete(reports, samples))
        reports[0]['generator']['p95_lateness_ns'] = 2_000_001
        self.assertFalse(smoke_complete(reports, samples))

    def test_committed_mode_requires_independent_write_evidence_from_every_case(self):
        evidence = reports()
        samples = [dict(beams=[dict(rss_kib=100)])]
        self.assertFalse(smoke_complete(evidence, samples, committed_writes=True))
        for report in evidence:
            report['persistence'] = 'committed'
            report['database_pool_size'] = 10
        self.assertTrue(smoke_complete(evidence, samples, committed_writes=True))
        evidence[0]['persistence'] = 'sandbox'
        self.assertFalse(smoke_complete(evidence, samples, committed_writes=True))

    def test_requested_concurrency_requires_the_complete_frame_workload(self):
        evidence = reports()
        samples = [dict(beams=[dict(rss_kib=100)])]
        self.assertFalse(smoke_complete(evidence, samples, rooms=2))
        for report in evidence:
            report['rooms'] = 2
            report['generator']['frames_sent'] = 128
        self.assertTrue(smoke_complete(evidence, samples, rooms=2))
        evidence[0]['generator']['frames_sent'] = 64
        self.assertFalse(smoke_complete(evidence, samples, rooms=2))

    def test_sampler_failure_still_cleans_owned_units_and_cannot_pass(self):
        owned = OwnedUnits(RUN)
        unit = f'vxpipe-diagnostic-generator-{RUN}-{LEAF}.service'
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'workload.log'
            log.write_text('DIAGNOSTIC_GENERATOR_UNIT ' + unit + '\n')
            process = Mock(pid=123, returncode=0)
            process.poll.return_value = None
            with patch('smoke_runner.stop_unit') as stop:
                result = watch(process, owned, log, sample=Mock(side_effect=ValueError('sample failed')))
            self.assertFalse(result['completed'])
            self.assertIn('sample failed', result['abort'])
            stop.assert_any_call(owned.scope, system=True)
            stop.assert_any_call(unit)

    def test_failed_launcher_kill_does_not_skip_generator_cleanup(self):
        owned = OwnedUnits(RUN)
        unit = f'vxpipe-diagnostic-generator-{RUN}-{LEAF}.service'
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'workload.log'
            log.write_text('DIAGNOSTIC_GENERATOR_UNIT ' + unit + '\n')
            process = Mock(pid=123, returncode=None)
            process.poll.return_value = None
            process.wait.side_effect = subprocess.TimeoutExpired('launcher', 5)
            with patch('smoke_runner.stop_unit') as stop, patch(
                    'smoke_runner.subprocess.run', side_effect=subprocess.TimeoutExpired('kill', 5)):
                result = watch(process, owned, log, sample=Mock(side_effect=ValueError('sample failed')))
            self.assertFalse(result['completed'])
            self.assertTrue(result['cleanup_errors'])
            stop.assert_any_call(unit)

    def test_replaced_measured_vm_cannot_report_completed(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'workload.log'
            log.write_text(''.join('DIAGNOSTIC_EXTERNAL_SMOKE ' + json.dumps(r) + '\n'
                                   for r in reports()))
            process = Mock(pid=123, returncode=0)
            process.poll.side_effect = [None, None, 0]
            with patch('smoke_runner.stop_unit'):
                result = watch(process, OwnedUnits(RUN), log,
                               sample=Mock(side_effect=[sample(900, 10), sample(901, 20)]),
                               sleep=lambda _: None)
            self.assertFalse(result['completed'])

    def test_bad_output_does_not_hide_later_owned_unit_from_cleanup(self):
        unit = f'vxpipe-diagnostic-generator-{RUN}-{LEAF}.service'
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'workload.log'
            log.write_text('DIAGNOSTIC_GENERATOR_UNIT wrong.service\n'
                           'DIAGNOSTIC_GENERATOR_UNIT wrong-again.service\n'
                           'DIAGNOSTIC_GENERATOR_UNIT ' + unit + '\n')
            process = Mock(pid=123, returncode=0)
            process.poll.return_value = None
            with patch('smoke_runner.stop_unit') as stop:
                result = watch(process, OwnedUnits(RUN), log,
                               sample=Mock(return_value=sample(900, 10)), sleep=lambda _: None)
            self.assertFalse(result['completed'])
            stop.assert_any_call(unit)


if __name__ == '__main__':
    unittest.main()
