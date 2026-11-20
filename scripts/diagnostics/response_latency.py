"""Reconstruct complete command-correlated completion/dispatch populations."""
from workload_profile import profile, PERIOD_NS

BOUNDARY = 'canonical-audio-completion-publication-to-dispatch-invocation-v1'
SOURCE_FIELDS = ('room_id', 'incarnation_id', 'participant_id', 'connection_id')


def identity(record):
    values = tuple(record[k] for k in SOURCE_FIELDS)
    if any(not isinstance(v, str) or not v for v in values):
        raise ValueError('invalid source identity')
    return values


def summarize(data, rooms, humans, workload):
    inputs = rooms * humans
    plan = profile(workload)
    sources, turns, events = data['sources'], data['turns'], data['events']
    indices = {str(i) for i in range(inputs)}
    if set(sources) != indices or set(turns) != indices or len({identity(s) for s in sources.values()}) != inputs:
        raise ValueError('incomplete sources')
    expected = {}
    for i in range(inputs):
        source = identity(sources[str(i)])
        schedule = plan.settlements(i, inputs, humans)
        rows = turns[str(i)]
        if len(rows) != len(schedule):
            raise ValueError('incomplete canonical turns')
        for n, (row, frame) in enumerate(zip(rows, schedule), 1):
            correlation, command = row['correlation_id'], row['command_id']
            if (type(row['turn']) is not int or row['turn'] != n
                    or any(not isinstance(v, str) or not v for v in (correlation, command))):
                raise ValueError('invalid canonical turn')
            key = source + (correlation, command)
            if key in expected:
                raise ValueError('duplicate canonical turn')
            offset = (frame-1) * PERIOD_NS + PERIOD_NS * i // inputs
            expected[key] = (plan.measurement_start_ns <= offset < plan.duration_ns, i, n)
    if len(events) != 2 * len(expected):
        raise ValueError('incomplete response events')
    observed, clocks, ordinals = {}, {}, {}
    for event in events:
        source = identity(event)
        key = source + (event['correlation_id'], event['command_id'])
        stage, at = event['stage'], event['at_us']
        room = source[:2]
        previous = observed.setdefault(key, {})
        if (key not in expected or type(at) is not int or at < clocks.get(room, at)
                or stage not in ('completed','dispatched') or stage in previous
                or (stage == 'dispatched' and 'completed' not in previous)):
            raise ValueError('conflicting response events')
        _, index, ordinal = expected[key]
        if stage == 'completed':
            if ordinal != ordinals.get(index, 1):
                raise ValueError('canonical completion order differs from trace')
            ordinals[index] = ordinal + 1
        clocks[room] = at
        previous[stage] = at
    durations = []
    for key, (measured, _, _) in expected.items():
        event = observed[key]
        elapsed = event['dispatched'] - event['completed']
        if measured:
            durations.append(elapsed)
    durations.sort()
    count = len(durations)
    return dict(count=count, p95_us=durations[(95*count+99)//100-1])


def complete(data, rooms, humans, workload):
    try:
        return data['boundary'] == BOUNDARY and data['summary'] == summarize(data, rooms, humans, workload)
    except (KeyError, TypeError, ValueError, IndexError, AttributeError):
        return False
