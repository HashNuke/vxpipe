"""Independent complete-population latency accounting."""
from copy import deepcopy
import unittest
from ingress_latency import summarize, complete
from workload_profile import profile


def evidence(mode='smoke', inputs=1):
    plan = profile(mode)
    samples = {str(i): [dict(sequence=s, ingress_us=-1_000_000_000+s*32000,
                            provider_us=-1_000_000_000+s*32000+10)
                       for s in range(plan.frame_count(i, inputs))] for i in range(inputs)}
    return dict(boundary='accepted-push-invocation-to-provider-receipt-v1', samples=samples,
                summary=dict(count=625*inputs if mode == 'warm' else 192*inputs, p95_us=10))


class IngressLatencyTest(unittest.TestCase):
    def test_exact_population_nearest_rank_and_delayed_tail(self):
        data = evidence('warm')
        for row in data['samples']['0'][750:]:
            row['provider_us'] = row['ingress_us'] + 9000
        self.assertEqual(summarize(data['samples'], 1, 'warm'), dict(count=625, p95_us=9000))
        self.assertFalse(complete(data, 1, 'warm'))
        data['summary']['p95_us'] = 9000
        self.assertTrue(complete(data, 1, 'warm'))

    def test_missing_duplicated_unordered_negative_and_forged_samples_fail(self):
        original = evidence('warm', 4)
        self.assertTrue(complete(original, 4, 'warm'))
        mutations = [lambda d: d['samples'].pop('3'),
                     lambda d: d['samples']['0'].pop(0),
                     lambda d: d['samples']['0'].reverse(),
                     lambda d: d['samples']['0'][0].update(provider_us=-1_000_000_001),
                     lambda d: d['samples']['0'][0].update(sequence=True),
                     lambda d: d['summary'].update(count=2499),
                     lambda d: d.update(boundary='observer-mailbox')]
        for mutate in mutations:
            data = deepcopy(original)
            mutate(data)
            self.assertFalse(complete(data, 4, 'warm'))

    def test_per_input_clocks_cannot_run_backwards_even_when_p95_is_unchanged(self):
        for field in ('ingress_us', 'provider_us', 'both'):
            data = evidence('warm')
            # Long overlapping intervals keep each mutated duration nonnegative.
            rows = data['samples']['0']
            for row in rows:
                row['provider_us'] += 100_000
            data['summary']['p95_us'] += 100_000
            for key in (('ingress_us', 'provider_us') if field == 'both' else (field,)):
                rows[200][key], rows[201][key] = rows[201][key], rows[200][key]
            self.assertFalse(complete(data, 1, 'warm'))

    def test_smoke_allows_zero_durations_and_negative_clock_values(self):
        data = evidence()
        for row in data['samples']['0']:
            row['provider_us'] = row['ingress_us']
        data['summary']['p95_us'] = 0
        self.assertTrue(complete(data, 1, 'smoke'))
