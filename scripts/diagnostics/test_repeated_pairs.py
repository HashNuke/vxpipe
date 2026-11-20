"""Six serial phases retain invalid evidence and alternate the declared order."""
from pathlib import Path
from copy import deepcopy
from measurement import ProcessSample, summarize
import json
import tempfile
import unittest
from unittest.mock import Mock
from repeated_pairs import run_cell
from test_paired_warm_results import cold_artifact, artifact
from test_response_latency import egress_evidence


class RepeatedPairsTest(unittest.TestCase):
    def runner(self, *, fail=None, changed_source=False, slow_ready=False):
        self.calls = []
        def run(command, **_options):
            self.calls.append(command)
            target = Path(command[command.index('--output') + 1])
            target.mkdir()
            workload = command[command.index('--workload') + 1]
            case = command[command.index('--case') + 1]
            value = cold_artifact() if workload == 'cold' else artifact()
            value['run_id'] = f'{len(self.calls):032x}'
            phase = value['smoke_reports'][0]
            phase.update(collection=case.endswith('-on'), operational_vad=case.startswith('reuse'))
            phase['response_egress'] = egress_evidence(workload)
            if changed_source and len(self.calls) == 2:
                value['provenance']['source_commit'] = 'c' * 40
            if slow_ready and phase['collection']:
                raw = phase['resource_samples']
                last = deepcopy(raw[-1])
                for offset in (100_000_000, 200_000_000, 300_000_000):
                    event = deepcopy(last)
                    for key in ('deadline_ns', 'read_started_ns', 'read_finished_ns'):
                        event[key] += offset
                    event['sample']['at_seconds'] += offset / 1e9
                    event['sample']['cpu_seconds'] += offset / 2e9
                    raw.append(event)
                interval = phase['generator']['resource_interval']
                interval.update(scheduled_end_ns=23_300_000_000, audio_start_ns=3_300_000_000, ready_at_ns=3_300_000_000,
                                preparation_duration_ns=2_300_000_000, preparation_cpu_seconds=1.15)
                interval['preparation_sample'].update(at_seconds=3.3, cpu_seconds=1.65)
                interval['summary'] = summarize([ProcessSample(**event['sample']) for event in raw])
                phase['generator']['audio_start_ns'] = 3_300_000_000
                value['resource_samples'] = deepcopy(raw)
            if fail == len(self.calls):
                value['completed'] = False
                value['abort'] = 'test invalid attempt'
            (target / 'report.json').write_text(json.dumps(value))
            return Mock(returncode=1 if fail == len(self.calls) else 0)
        return run

    def test_three_pairs_alternate_and_preserve_each_pair(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'cell'
            result = run_cell('cold', 'fallback', 1, 1, target, run=self.runner())
            self.assertEqual([c[c.index('--case')+1] for c in self.calls],
                             ['fallback-off', 'fallback-on', 'fallback-on', 'fallback-off', 'fallback-off', 'fallback-on'])
            self.assertTrue(result['performance_cell_complete'])
            self.assertFalse(result['milestone_acceptance_complete'])
            self.assertEqual(len(result['pairs']), 3)
            self.assertEqual(result['readiness']['off_p95_ns'], 2_000_000_000)
            self.assertTrue(result['readiness']['passed'])
            self.assertTrue((target / 'pair-3.json').exists())

    def test_cold_readiness_regression_fails_despite_valid_resource_budgets(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = run_cell('cold', 'fallback', 1, 1, Path(temporary) / 'cell',
                              run=self.runner(slow_ready=True))
            self.assertEqual(len(self.calls), 6)
            self.assertTrue(all(pair['measured_gates_pass'] for pair in result['pairs']))
            self.assertFalse(result['readiness']['passed'])
            self.assertFalse(result['performance_cell_complete'])

    def test_source_change_aborts_before_publishing_a_pair(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = run_cell('warm', 'fallback', 1, 1, Path(temporary) / 'cell',
                              run=self.runner(changed_source=True))
            self.assertEqual(len(self.calls), 2)
            self.assertEqual(result['pairs'], [])
            self.assertEqual(result['invalid_phase'], 'pair-1-on')

    def test_invalid_phase_stops_without_retry_or_deleting_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'cell'
            result = run_cell('warm', 'fallback', 1, 1, target, run=self.runner(fail=2))
            self.assertEqual(len(self.calls), 2)
            self.assertFalse(result['performance_cell_complete'])
            self.assertEqual(result['invalid_phase'], 'pair-1-on')
            self.assertTrue((target / 'pair-1-on' / 'report.json').exists())
            self.assertFalse((target / 'pair-2-on').exists())
            with self.assertRaises(FileExistsError):
                run_cell('warm', 'fallback', 1, 1, target, run=self.runner())


if __name__ == '__main__':
    unittest.main()
