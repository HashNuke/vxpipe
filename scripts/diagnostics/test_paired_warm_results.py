import unittest
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from copy import deepcopy
from paired_warm_results import compare_validated, validate_artifact
from dataclasses import asdict
from measurement import ProcessSample, summarize
from test_ingress_latency import evidence as ingress_evidence
from test_response_latency import evidence as response_evidence, egress_evidence
from test_smoke_runner import sample


def phase(enabled, cpu=0.03, rss=200000, ingress=300, dispatch=300):
    return dict(collection=enabled, operational_vad=False, rooms=1, inputs_per_room=1,
                run_id=('b' if enabled else 'a') * 32,
                provenance=dict(source_commit='a' * 40, file_sha256={'model.onnx': 'b' * 64}),
                resources=dict(cpu_cores=cpu, cpu_seconds=cpu * 20,
                               duration_seconds=20, process_high_water_kib=rss),
                ingress=dict(count=625, p95_us=ingress),
                dispatch=dict(count=10, p95_us=dispatch))


def artifact():
    raw = [dict(deadline_ns=6_000_000_000 + ms * 1_000_000,
                read_started_ns=6_000_000_000 + ms * 1_000_000,
                read_finished_ns=6_000_000_000 + ms * 1_000_000,
                sample=asdict(ProcessSample(123, 77, 6 + ms / 1000, 3 + ms / 2000,
                                           100, 100, 2, ms == 0)))
           for ms in range(0, 20001, 100)]
    report = dict(collection=False, operational_vad=False, rooms=1, inputs_per_room=1,
                  workload='warm', persistence='committed', database_pool_size=10,
                  measured_turn_counts={'0': 10}, resource_samples=raw,
                  ingress_latency=ingress_evidence('warm'), response_dispatch=response_evidence('warm'),
                  generator=dict(fixture_sha256='d' * 64, frames_sent=782, measured_frames_sent=625,
                    measured_p95_lateness_ns=1000, p95_lateness_ns=1000,
                    audio_start_ns=1_000_000_000, elapsed_ns=25_000_000_000,
                    resource_interval=dict(pid=123, start_ticks=77, scheduled_start_ns=6_000_000_000,
                        scheduled_end_ns=26_000_000_000, timing_valid=True,
                        timing_contract='boundary-2ms-no-skipped-slot-v1', start_lateness_ns=0,
                        end_lateness_ns=0, maximum_lateness_ns=0, maximum_sample_gap_ns=100_000_000,
                        summary=summarize([ProcessSample(**e['sample']) for e in raw]))))
    return dict(completed=True, exit_code=0, abort=None, cleanup_errors=[], retained_databases=[],
                smoke_reports=[report], samples=[sample(123, 77)], resource_samples=deepcopy(raw),
                run_id='a' * 32, provenance=phase(False)['provenance'])


def cold_artifact():
    value = artifact()
    report = value['smoke_reports'][0]
    raw = [dict(deadline_ns=1_000_000_000 + ms * 1_000_000,
                read_started_ns=1_000_000_000 + ms * 1_000_000,
                read_finished_ns=1_000_000_000 + ms * 1_000_000,
                sample=asdict(ProcessSample(123, 77, 1 + ms / 1000, .5 + ms / 2000,
                                           100, 100, 2, ms == 0)))
           for ms in range(0, 22001, 100)]
    report.update(workload='cold', resource_samples=raw, ingress_latency=ingress_evidence('cold'),
                  response_dispatch=response_evidence('cold'), response_egress=egress_evidence('cold'))
    report['ingress_latency']['summary']['count'] = 625
    report['generator'].update(frames_sent=625, audio_start_ns=3_000_000_000, elapsed_ns=20_000_000_000)
    report['generator']['resource_interval'].update(scheduled_start_ns=1_000_000_000,
        scheduled_end_ns=23_000_000_000, audio_start_ns=3_000_000_000, ready_at_ns=3_000_000_000,
        preparation_duration_ns=2_000_000_000, preparation_cpu_seconds=1,
        preparation_sample=asdict(ProcessSample(123,77,3,1.5,100,100,2)),
        summary=summarize([ProcessSample(**e['sample']) for e in raw]))
    value['resource_samples'] = deepcopy(raw)
    return value


class PairedWarmResultsTest(unittest.TestCase):

    def test_cold_artifact_includes_preparation_and_cannot_pair_with_warm(self):
        cold = validate_artifact(cold_artifact())
        self.assertEqual(cold['workload'], 'cold')
        self.assertEqual(cold['resources']['duration_seconds'], 22)
        self.assertEqual(cold['preparation_duration_ns'], 2_000_000_000)
        on = deepcopy(cold)
        on['collection'], on['run_id'] = True, 'b' * 32
        result = compare_validated(cold, on)
        self.assertEqual(result['workload'], 'cold')
        self.assertTrue(result['measured_gates_pass'])
        warm = validate_artifact(artifact())
        with self.assertRaises(ValueError):
            compare_validated(warm, on)
        for key, bad in [('preparation_duration_ns', 15_000_000_001),
                         ('preparation_cpu_seconds', -1), ('audio_start_ns', 4_000_000_000),
                         ('scheduled_start_ns', 3_000_000_000)]:
            wrong = cold_artifact()
            wrong['smoke_reports'][0]['generator']['resource_interval'][key] = bad
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_artifact(wrong)

    def test_cold_ready_sample_cannot_hide_memory_peak_or_nonmonotonic_cpu(self):
        for key, value in [('high_water_kib', 65536), ('cpu_seconds', 9.2), ('threads', True)]:
            wrong = cold_artifact()
            interval = wrong['smoke_reports'][0]['generator']['resource_interval']
            interval['preparation_sample'][key] = value
            if key == 'cpu_seconds':
                interval['preparation_cpu_seconds'] = value - .5
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_artifact(wrong)

    def test_cold_ready_sample_peak_is_retained_when_summary_includes_it(self):
        value = cold_artifact()
        interval = value['smoke_reports'][0]['generator']['resource_interval']
        interval['preparation_sample']['high_water_kib'] = 65536
        interval['summary']['process_high_water_kib'] = 65536
        self.assertEqual(validate_artifact(value)['resources']['process_high_water_kib'], 65536)

    def test_actual_emitted_fixture_hash_must_match_between_phases(self):
        off, on = artifact(), artifact()
        on['run_id'] = 'b' * 32
        on['smoke_reports'][0]['collection'] = True
        off['smoke_reports'][0]['generator']['fixture_sha256'] = 'a' * 64
        on['smoke_reports'][0]['generator']['fixture_sha256'] = 'b' * 64
        with self.assertRaises(ValueError):
            compare_validated(validate_artifact(off), validate_artifact(on))

    def test_egress_is_validated_and_compared_when_both_phases_supply_it(self):
        off, on = artifact(), artifact()
        on['run_id'] = 'b' * 32
        on['smoke_reports'][0]['collection'] = True
        for value in (off, on):
            value['smoke_reports'][0]['response_egress'] = egress_evidence('warm')
        result = compare_validated(validate_artifact(off), validate_artifact(on))
        self.assertTrue(result['latency']['egress']['passed'])
        self.assertNotIn('egress_latency', result['missing_acceptance_evidence'])
        self.assertFalse(result['milestone_acceptance_complete'])
        bad = deepcopy(on)
        bad['smoke_reports'][0]['response_egress']['events'][-1]['output_id'] = 'wrong'
        with self.assertRaises(ValueError):
            validate_artifact(bad)
        unrelated = deepcopy(on)
        egress = unrelated['smoke_reports'][0]['response_egress']
        for item in list(egress['sources'].values()) + egress['events']:
            item['room_id'] = 'unrelated-room'
        with self.assertRaises(ValueError):
            validate_artifact(unrelated)

    def test_egress_regression_and_asymmetric_evidence_cannot_pass(self):
        off, on = phase(False), phase(True)
        off['egress'] = dict(count=10, p95_us=500)
        with self.assertRaises(ValueError):
            compare_validated(off, on)
        on['egress'] = dict(count=10, p95_us=2500)
        self.assertTrue(compare_validated(off, on)['measured_gates_pass'])
        on['egress']['p95_us'] = 2501
        self.assertFalse(compare_validated(off, on)['measured_gates_pass'])
        on['egress']['p95_us'] = float('nan')
        with self.assertRaises(ValueError):
            compare_validated(off, on)

    def test_cli_rejects_invalid_elapsed_reset_and_turn_population(self):
        for mutation in ('elapsed', 'reset', 'turns', 'dirty', 'extra_provenance'):
            off, on = artifact(), artifact()
            on['run_id'] = 'b' * 32
            report = on['smoke_reports'][0]
            report['collection'] = True
            if mutation == 'elapsed':
                report['generator']['elapsed_ns'] = float('inf')
            elif mutation == 'reset':
                report['resource_samples'][0]['sample']['interval_start'] = 'not reset'
                on['resource_samples'] = deepcopy(report['resource_samples'])
            elif mutation == 'turns':
                report['measured_turn_counts'] = ['0']
            elif mutation == 'dirty':
                on['provenance']['worktree_dirty'] = float('inf')
            else:
                on['provenance']['extra'] = float('inf')
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                paths = [Path(directory) / name for name in ('off.json', 'on.json')]
                for path, data in zip(paths, (off, on)):
                    path.write_text(json.dumps(data))
                run = subprocess.run([sys.executable, str(Path(__file__).with_name('paired_warm_results.py')),
                                      *map(str, paths)], capture_output=True, text=True)
                self.assertEqual(run.returncode, 2, run.stdout + run.stderr)
                self.assertIn('invalid pair:', run.stderr)
                self.assertNotIn('Traceback', run.stderr)

    def test_report_preserves_both_phase_provenance_and_dirty_status(self):
        off, on = phase(False), phase(True)
        off['provenance']['worktree_dirty'] = False
        on['provenance']['worktree_dirty'] = True
        result = compare_validated(off, on)
        self.assertEqual(result['provenance'], {'off': off['provenance'], 'on': on['provenance']})
        self.assertTrue(result['provenance']['on']['worktree_dirty'])

    def test_artifact_revalidates_raw_evidence_and_clean_completion(self):
        good = artifact()
        self.assertEqual(validate_artifact(good)['ingress']['count'], 625)
        changes = [('completed', False), ('exit_code', 1), ('exit_code', False),
                   ('abort', 'watchdog'), ('cleanup_errors', ['stop failed']),
                   ('retained_databases', ['scratch']), ('smoke_reports', []),
                   ('samples', []), ('resource_samples', [])]
        for key, value in changes:
            wrong = deepcopy(good)
            wrong[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_artifact(wrong)
        for mutate in [
            lambda r: r['generator'].update(frames_sent=781),
            lambda r: r['ingress_latency']['summary'].update(p95_us=999999),
            lambda r: r['response_dispatch']['summary'].update(count=1),
            lambda r: r['generator']['resource_interval']['summary'].update(cpu_cores=0),
            lambda r: r.update(workload='smoke'),
            lambda r: r.update(persistence='sandbox'),
        ]:
            wrong = deepcopy(good)
            mutate(wrong['smoke_reports'][0])
            with self.assertRaises(ValueError):
                validate_artifact(wrong)

    def test_reuse_cpu_target_and_invalid_provenance(self):
        off, on = phase(False), phase(True, cpu=.06)
        off['operational_vad'] = on['operational_vad'] = True
        result = compare_validated(off, on)
        self.assertEqual(result['cpu']['original_target_cores'], .025)
        self.assertFalse(result['cpu']['within_original_target'])
        for bad in [{}, {'source_commit': 'a' * 40, 'file_sha256': {}},
                    {'source_commit': 'unknown', 'file_sha256': {'x': 'b' * 64}}]:
            off['provenance'] = on['provenance'] = bad
            with self.assertRaises(ValueError):
                compare_validated(off, on)

    def test_cpu_cost_is_reported_advisory_and_never_makes_otherwise_valid_gates_fail(self):
        result = compare_validated(phase(False), phase(True, cpu=0.20))
        self.assertTrue(result['measured_gates_pass'])
        self.assertFalse(result['cpu']['within_original_target'])
        self.assertTrue(result['cpu']['advisory'])
        self.assertNotIn('database_cpu', result['missing_acceptance_evidence'])
        self.assertNotIn('inference_coverage', result['missing_acceptance_evidence'])
        self.assertNotIn('acoustic_accuracy', result['missing_acceptance_evidence'])
        self.assertFalse(result['milestone_acceptance_complete'])
        self.assertIn('egress_latency', result['missing_acceptance_evidence'])

    def test_memory_and_latency_regressions_still_fail(self):
        for enabled in [phase(True, rss=400000), phase(True, ingress=2301),
                        phase(True, dispatch=2301)]:
            with self.subTest(enabled=enabled):
                self.assertFalse(compare_validated(phase(False), enabled)['measured_gates_pass'])

    def test_budget_boundary_and_ten_percent_latency_allowance(self):
        off = phase(False, ingress=30000, dispatch=30000)
        on = phase(True, ingress=33000, dispatch=33000, rss=200000 + 136 * 1024)
        self.assertTrue(compare_validated(off, on)['measured_gates_pass'])
        on['dispatch']['p95_us'] += 1
        self.assertFalse(compare_validated(off, on)['measured_gates_pass'])

    def test_only_matching_topology_mode_source_and_distinct_phase_runs_are_comparable(self):
        changes = [('collection', False), ('operational_vad', True), ('rooms', 2),
                   ('inputs_per_room', 2), ('run_id', 'a' * 32),
                   ('provenance', dict(source_commit='c' * 40, file_sha256={'model.onnx': 'b' * 64})),
                   ('provenance', dict(source_commit='a' * 40, file_sha256={'model.onnx': 'c' * 64}))]
        for key, value in changes:
            with self.subTest(key=key, value=value):
                on = phase(True)
                on[key] = value
                with self.assertRaises(ValueError):
                    compare_validated(phase(False), on)

    def test_nonfinite_or_missing_measurements_cannot_pass(self):
        for bad in [float('nan'), float('inf'), None, True]:
            with self.subTest(bad=bad):
                on = phase(True)
                on['resources']['cpu_cores'] = bad
                with self.assertRaises(ValueError):
                    compare_validated(phase(False), on)
        on = phase(True)
        del on['dispatch']['p95_us']
        with self.assertRaises(ValueError):
            compare_validated(phase(False), on)


if __name__ == '__main__':
    unittest.main()
