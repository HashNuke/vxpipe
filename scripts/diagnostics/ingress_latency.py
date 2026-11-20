"""Recompute ingress latency from the complete same-VM frame receipt population."""
from workload_profile import profile, PERIOD_NS

BOUNDARY = 'accepted-push-invocation-to-provider-receipt-v1'


def summarize(samples, inputs, workload):
    plan = profile(workload)
    if not isinstance(samples, dict) or set(samples) != {str(i) for i in range(inputs)}:
        raise ValueError('missing input latency samples')
    durations = []
    for index in range(inputs):
        rows = samples[str(index)]
        if not isinstance(rows, list) or len(rows) != plan.frame_count(index, inputs):
            raise ValueError('missing frame latency samples')
        previous = None
        for sequence, row in enumerate(rows):
            if (not isinstance(row, dict)
                    or any(type(row.get(k)) is not int for k in ('sequence', 'ingress_us', 'provider_us'))
                    or row['sequence'] != sequence or row['provider_us'] < row['ingress_us']):
                raise ValueError('invalid frame latency sample')
            if previous is not None and any(row[k] < previous[k] for k in ('ingress_us', 'provider_us')):
                raise ValueError('backwards frame latency clock')
            previous = row
            offset = sequence * PERIOD_NS + PERIOD_NS * index // inputs
            if plan.measurement_start_ns <= offset < plan.duration_ns:
                durations.append(row['provider_us'] - row['ingress_us'])
    durations.sort()
    count = len(durations)
    return dict(count=count, p95_us=durations[(95 * count + 99) // 100 - 1])


def complete(evidence, inputs, workload):
    try:
        return (evidence['boundary'] == BOUNDARY
                and evidence['summary'] == summarize(evidence['samples'], inputs, workload))
    except (KeyError, TypeError, ValueError, IndexError):
        return False
