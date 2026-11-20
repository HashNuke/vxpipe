"""Compare two validated warm reports; this is partial performance evidence only."""
import argparse
import json
import math
from pathlib import Path
import re

from smoke_runner import smoke_complete


def number(value, name, *, positive=False):
    if (type(value) not in (int, float) or not math.isfinite(value)
            or value < 0 or (positive and value == 0)):
        raise ValueError(f'invalid {name}')
    return value


def validate_phase(phase):
    try:
        for key in ('collection', 'operational_vad'):
            if type(phase[key]) is not bool:
                raise ValueError(f'invalid {key}')
        rooms, humans = phase['rooms'], phase['inputs_per_room']
        if (type(rooms) is not int or type(humans) is not int
                or rooms < 1 or humans not in (1, 2) or rooms * humans > 16):
            raise ValueError('invalid topology')
        if not re.fullmatch('[0-9a-f]{32}', phase['run_id']):
            raise ValueError('invalid run identity')
        source = phase['provenance']
        if 'worktree_dirty' in source and type(source['worktree_dirty']) is not bool:
            raise ValueError('invalid dirty-worktree provenance')
        hashes = source['file_sha256']
        if (not re.fullmatch('[0-9a-f]{40}', source['source_commit'])
                or not isinstance(hashes, dict) or not hashes
                or any(not isinstance(path, str) or not path
                       or not isinstance(digest, str)
                       or not re.fullmatch('[0-9a-f]{64}', digest)
                       for path, digest in hashes.items())):
            raise ValueError('invalid provenance')
        for key in ('cpu_cores', 'cpu_seconds', 'duration_seconds', 'process_high_water_kib'):
            number(phase['resources'][key], key, positive=key in ('duration_seconds', 'process_high_water_kib'))
        for key in ('ingress', 'dispatch') + (('egress',) if 'egress' in phase else ()):
            if type(phase[key]['count']) is not int or phase[key]['count'] <= 0:
                raise ValueError('invalid latency population')
            number(phase[key]['p95_us'], key)
    except (KeyError, TypeError, OverflowError) as error:
        raise ValueError('missing or malformed warm phase') from error


def validate_artifact(artifact):
    """Recompute workload validity rather than trusting the saved completed flag."""
    try:
        if (artifact['completed'] is not True or type(artifact['exit_code']) is not int
                or artifact['exit_code'] != 0 or artifact['abort'] is not None
                or artifact['cleanup_errors'] != [] or artifact['retained_databases'] != []
                or len(artifact['smoke_reports']) != 1):
            raise ValueError('incomplete run or cleanup')
        report = artifact['smoke_reports'][0]
        if (type(report['generator']['elapsed_ns']) is not int
                or not isinstance(report['measured_turn_counts'], dict)
                or not isinstance(report['resource_samples'], list)
                or not report['resource_samples']
                or any(event['sample']['interval_start'] is not (index == 0)
                       for index, event in enumerate(report['resource_samples']))):
            raise ValueError('invalid elapsed time, turn population or interval reset')
        phase = dict(collection=report['collection'], operational_vad=report['operational_vad'],
                     rooms=report['rooms'], inputs_per_room=report['inputs_per_room'],
                     run_id=artifact['run_id'], provenance=artifact['provenance'],
                     resources=report['generator']['resource_interval']['summary'],
                     ingress=report['ingress_latency']['summary'],
                     dispatch=report['response_dispatch']['summary'])
        has_egress = 'response_egress' in report
        if has_egress:
            phase['egress'] = report['response_egress']['summary']
        validate_phase(phase)
        if (artifact['resource_samples'] != report['resource_samples']
                or not smoke_complete(artifact['smoke_reports'], artifact['samples'],
                    rooms=phase['rooms'], inputs_per_room=phase['inputs_per_room'],
                    workload='warm', selected_case=(phase['operational_vad'], phase['collection']),
                    require_egress=has_egress)):
            raise ValueError('invalid warm workload evidence')
        return phase
    except (KeyError, TypeError, IndexError, OverflowError) as error:
        raise ValueError('missing or malformed warm artifact') from error


def compare_validated(off, on):
    validate_phase(off)
    validate_phase(on)
    if (off['collection'] is not False or on['collection'] is not True
            or off['run_id'] == on['run_id']
            or ('egress' in off) != ('egress' in on)
            or any(off[key] != on[key] for key in ('operational_vad', 'rooms', 'inputs_per_room'))
            or any(off['provenance'][key] != on['provenance'][key]
                   for key in ('source_commit', 'file_sha256'))):
        raise ValueError('phases must be distinct off/on runs of matching source, topology and mode')
    inputs = off['rooms'] * off['inputs_per_room']
    target = .02 + .005 * inputs if off['operational_vad'] else .05 + .03 * inputs
    cpu_delta = on['resources']['cpu_cores'] - off['resources']['cpu_cores']
    rss_delta = on['resources']['process_high_water_kib'] - off['resources']['process_high_water_kib']
    rss_limit = (128 + 8 * inputs) * 1024
    latencies = {}
    for key in ('ingress', 'dispatch') + (('egress',) if 'egress' in off else ()):
        delta = on[key]['p95_us'] - off[key]['p95_us']
        limit = max(2000, off[key]['p95_us'] * .1)
        latencies[key] = dict(off=off[key], on=on[key], delta_us=delta,
                              limit_us=limit, passed=delta <= limit)
    return dict(mode='reuse' if off['operational_vad'] else 'fallback',
                rooms=off['rooms'], inputs_per_room=off['inputs_per_room'],
                off_run_id=off['run_id'], on_run_id=on['run_id'],
                provenance=dict(off=off['provenance'], on=on['provenance']),
                cpu=dict(off=off['resources'], on=on['resources'], delta_cores=cpu_delta,
                         original_target_cores=target, within_original_target=cpu_delta <= target,
                         advisory=True),
                rss=dict(delta_kib=rss_delta, limit_kib=rss_limit, passed=rss_delta <= rss_limit),
                latency=latencies,
                measured_gates_pass=rss_delta <= rss_limit and all(x['passed'] for x in latencies.values()),
                milestone_acceptance_complete=False,
                missing_acceptance_evidence=([] if 'egress' in off else ['egress_latency']) +
                                            ['database_cpu', 'inference_coverage',
                                             'cold_phases', 'repeated_topology_matrix',
                                             'acoustic_accuracy', 'live_acceptance'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('off', type=Path)
    parser.add_argument('on', type=Path)
    args = parser.parse_args()
    try:
        result = compare_validated(validate_artifact(json.loads(args.off.read_text())),
                                   validate_artifact(json.loads(args.on.read_text())))
        output = json.dumps(result, indent=2, allow_nan=False)
    except (OSError, ValueError) as error:
        parser.exit(2, f'invalid pair: {error}\n')
    print(output)
    return 0 if result['measured_gates_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
