"""Independent command-correlated dispatch latency validation."""
from copy import deepcopy
import unittest
from workload_profile import profile
from response_latency import complete, summarize


def evidence(mode='smoke', rooms=1, humans=1):
    inputs = rooms * humans
    sources = {str(i): dict(room_id=f'room-{i//humans}', incarnation_id=f'inc-{i//humans}',
                            participant_id=f'human-{i}', connection_id=f'connection-{i}') for i in range(inputs)}
    turns = {str(i): [dict(turn=n, correlation_id=f'turn-{i}-{n}', command_id=f'command-{i}-{n}')
                      for n, _ in enumerate(profile(mode).settlements(i, inputs, humans), 1)] for i in range(inputs)}
    events = [dict(**source, correlation_id=row['correlation_id'], command_id=row['command_id'], stage=stage,
                   at_us=-1_000_000+row['turn']*100_000+int(i)*1000+(10 if stage=='dispatched' else 0))
              for i, source in sources.items() for row in turns[i] for stage in ('completed','dispatched')]
    events.sort(key=lambda e: e['at_us'])
    data = dict(boundary='canonical-audio-completion-publication-to-dispatch-invocation-v1',
                sources=sources, turns=turns, events=events)
    data['summary'] = summarize(data, rooms, humans, mode)
    return data


class ResponseLatencyTest(unittest.TestCase):
    def test_fixed_cohort_and_late_dispatch(self):
        data = evidence('warm')
        self.assertEqual(data['summary'], dict(count=10, p95_us=10))
        data['events'][-1]['at_us'] += 50_000_000
        self.assertFalse(complete(data,1,1,'warm'))
        data['summary']['p95_us'] += 50_000_000
        self.assertTrue(complete(data,1,1,'warm'))

    def test_missing_duplicate_cross_source_and_reversed_events_fail(self):
        original = evidence('warm',2,2)
        self.assertGreaterEqual(original['summary']['count'],40)
        self.assertTrue(complete(original,2,2,'warm'))
        for mutate in [lambda d:d['events'].pop(), lambda d:d['events'].append(d['events'][0]),
                       lambda d:d['events'][0].update(connection_id='other'),
                       lambda d:d['events'][1].update(command_id='other'),
                       lambda d:d['events'].reverse(), lambda d:d['turns']['0'].pop(),
                       lambda d:d['sources'].pop('3')]:
            data=deepcopy(original);mutate(data)
            self.assertFalse(complete(data,2,2,'warm'))

    def test_canonical_order_cannot_move_a_slow_measured_turn_into_warmup(self):
        data=evidence('warm')
        data['events'][-1]['at_us'] += 50_000_000
        data['summary']['p95_us'] += 50_000_000
        self.assertTrue(complete(data,1,1,'warm'))
        rows=data['turns']['0']
        for key in ('correlation_id','command_id'):
            rows[0][key],rows[-1][key]=rows[-1][key],rows[0][key]
        data['summary']['p95_us']=10
        self.assertFalse(complete(data,1,1,'warm'))

    def test_signed_timestamps_allow_equal_boundaries(self):
        data=evidence()
        for i in range(0,len(data['events']),2):
            data['events'][i+1]['at_us']=data['events'][i]['at_us']
        data['summary']['p95_us']=0
        self.assertTrue(complete(data,1,1,'smoke'))
