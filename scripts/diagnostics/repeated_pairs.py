"""Run one declared topology cell as three serial, alternating off/on pairs.

Optional informational measurement: requires an otherwise quiet host. Stops on
invalid evidence and retains every attempt; measured costs never stop a run.
Does not deploy or run providers. Complete means data collected, not costs approved.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from paired_warm_results import compare_validated, validate_artifact


def write(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def run_cell(workload, mode, rooms, humans, output, *, run=subprocess.run):
    shapes = [(1, 1), (8, 2)] if workload == 'cold' else [(1, 1), (2, 2), (16, 1), (8, 2)]
    if workload not in ('warm', 'cold') or mode not in ('fallback', 'reuse') or (rooms, humans) not in shapes:
        raise ValueError('unsupported declared cell')
    output.mkdir(parents=True, exist_ok=False)
    result = dict(workload=workload, mode=mode, rooms=rooms, inputs_per_room=humans,
                  attempts=[], pairs=[], performance_cell_complete=False,
                  milestone_acceptance_complete=False)
    manifest = output / 'manifest.json'
    write(manifest, result)
    run_ids = set()
    provenance = None
    for pair in range(1, 4):
        phases = {}
        for enabled in ((False, True) if pair % 2 else (True, False)):
            state = 'on' if enabled else 'off'
            label = f'pair-{pair}-{state}'
            command = [sys.executable, str(Path(__file__).with_name('smoke_runner.py')),
                       '--workload', workload, '--case', f'{mode}-{state}',
                       '--rooms', str(rooms), '--inputs-per-room', str(humans),
                       '--output', str(output / label)]
            result['attempts'].append(dict(phase=label, command=command))
            write(manifest, result)
            try:
                execution = run(command, check=False)
                if execution.returncode != 0:
                    raise ValueError('runner did not complete successfully')
                phase = validate_artifact(json.loads((output / label / 'report.json').read_text()))
                if (phase.get('workload') != workload or phase['operational_vad'] != (mode == 'reuse')
                        or phase['collection'] != enabled or phase['rooms'] != rooms
                        or phase['inputs_per_room'] != humans or 'egress' not in phase
                        or phase.get('fixture_sha256') is None
                        or phase['run_id'] in run_ids):
                    raise ValueError('phase differs from requested cell or duplicates a run')
                source = {key: phase['provenance'][key] for key in ('source_commit', 'file_sha256')}
                source['fixture_sha256'] = phase['fixture_sha256']
                if provenance is not None and source != provenance:
                    raise ValueError('source changed during repeated pairs')
                provenance = source
                run_ids.add(phase['run_id'])
                phases[state] = phase
            except (OSError, ValueError) as error:
                result.update(invalid_phase=label, error=str(error))
                write(manifest, result)
                return result
        comparison = compare_validated(phases['off'], phases['on'])
        write(output / f'pair-{pair}.json', comparison)
        result['pairs'].append(comparison)
        write(manifest, result)
    if workload == 'cold':
        # Nearest-rank p95 across three repetitions is their maximum.
        off = max(p['preparation_duration_ns']['off'] for p in result['pairs'])
        on = max(p['preparation_duration_ns']['on'] for p in result['pairs'])
        limit = max(100_000_000, off * .1)
        result['readiness'] = dict(off_p95_ns=off, on_p95_ns=on, delta_ns=on-off,
                                   limit_ns=limit, passed=on-off <= limit,
                                   within_original_target=on-off <= limit, advisory=True)
    result['performance_cell_complete'] = True
    result['cost_targets_within_original_limits'] = (
        all(pair['cost_targets_within_original_limits'] for pair in result['pairs'])
        and result.get('readiness', {}).get('within_original_target', True))
    result['worst'] = dict(
        cpu_delta_cores=max(p['cpu']['delta_cores'] for p in result['pairs']),
        rss_delta_kib=max(p['rss']['delta_kib'] for p in result['pairs']),
        latency_delta_us={key: max(p['latency'][key]['delta_us'] for p in result['pairs'])
                          for key in ('ingress', 'dispatch', 'egress')})
    write(manifest, result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workload', choices=('warm', 'cold'), required=True)
    parser.add_argument('--mode', choices=('fallback', 'reuse'), required=True)
    parser.add_argument('--rooms', type=int, required=True)
    parser.add_argument('--inputs-per-room', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = run_cell(args.workload, args.mode, args.rooms, args.inputs_per_room, args.output)
    print(json.dumps({key: result[key] for key in ('workload', 'mode', 'rooms', 'inputs_per_room',
                                                  'performance_cell_complete', 'milestone_acceptance_complete')}))
    return 0 if result['performance_cell_complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
