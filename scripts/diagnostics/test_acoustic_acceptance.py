import unittest
import tempfile
import shutil
import json
from pathlib import Path
from unittest.mock import patch
import acoustic_acceptance
from acoustic_acceptance import evaluate, transform_band, build_variants


class AcousticAcceptanceTest(unittest.TestCase):
    def test_build_rejects_changed_frozen_labels_before_creating_output(self):
        with tempfile.TemporaryDirectory() as directory:
            fixtures = Path(directory) / 'fixtures'
            shutil.copytree(acoustic_acceptance.FIXTURES, fixtures)
            reference = json.loads((fixtures / 'reference.json').read_text())
            reference['sources'][0]['onset'] = [12000, 12160]
            (fixtures / 'reference.json').write_text(json.dumps(reference))
            output = Path(directory) / 'output'
            with patch.object(acoustic_acceptance, 'FIXTURES', fixtures):
                with self.assertRaisesRegex(ValueError, 'frozen reference checksum mismatch'):
                    acoustic_acceptance.build(output)
            self.assertFalse(output.exists())

    def test_boundary_error_preserves_reference_uncertainty(self):
        report = evaluate({'onset': [100, 120], 'end': [900, 940]},
                          [{'onset': 130, 'end': 920}], 1000)
        self.assertEqual(report['onset']['signed_error_ms'], [10, 30])
        self.assertEqual(report['end']['signed_error_ms'], [-20, 20])
        self.assertEqual(report['end']['absolute_error_ms'], [0, 20])
        self.assertEqual(report['incomplete_rate'], 0)

    def test_internal_pause_is_reported_without_becoming_false_positive(self):
        report = evaluate({'onset': [100, 120], 'end': [900, 940]},
                          [{'onset': 110, 'end': 400}, {'onset': 600, 'end': 930}], 1000)
        self.assertEqual(report['internal_segment_count'], 1)
        self.assertEqual(report['end']['signed_error_ms'], [-10, 30])
        self.assertNotIn('false_positive_count', report)

    def test_missing_boundaries_are_incomplete_not_zero_error(self):
        report = evaluate({'onset': [100, 120], 'end': [900, 940]}, [], 1000)
        self.assertEqual(report['incomplete_rate'], 1)
        self.assertIsNone(report['onset'])
        self.assertIsNone(report['end'])
        report = evaluate({'onset': [100, 120], 'end': [900, 940]},
                          [{'onset': 110, 'end': None}], 1000)
        self.assertEqual(report['incomplete_rate'], 1)
        self.assertIsNone(report['end'])

    def test_outside_segments_are_separate_and_raw_evidence_preserved(self):
        segments = [{'onset': 0, 'end': 50}, {'onset': 110, 'end': 930},
                    {'onset': 1000, 'end': 1100}]
        report = evaluate({'onset': [100, 120], 'end': [900, 940]}, segments, 1000)
        self.assertEqual(report['before_reference_segment_indices'], [0])
        self.assertEqual(report['after_reference_segment_indices'], [2])
        self.assertEqual(report['internal_segment_count'], 0)
        self.assertEqual(report['raw_segments'], segments)
        self.assertEqual(report['onset']['signed_error_ms'], [-10, 10])

    def test_pause_resume_boundaries_report_missing_and_ambiguous_matches(self):
        reference = {'onset': [100, 120], 'end': [1900, 1940],
                     'internal': {'end': [900, 940], 'resumed_onset': [1100, 1120]}}
        segments = [{'onset': 110, 'end': 930}, {'onset': 1110, 'end': 1920}]
        report = evaluate(reference, segments, 1000)
        self.assertEqual(report['pause_resume']['first_end']['status'], 'unique')
        self.assertEqual(report['pause_resume']['resumed_onset']['candidates'][0]['error']['signed_error_ms'], [-10, 10])
        continuous = evaluate(reference, [{'onset': 110, 'end': 1920}], 1000)
        self.assertEqual(continuous['pause_resume']['first_end']['status'], 'missing')
        extra = evaluate(reference, [{'onset': 110, 'end': 400},
                         {'onset': 600, 'end': 930}, segments[1]], 1000)
        self.assertEqual(extra['pause_resume']['first_end']['status'], 'ambiguous')

    def test_pause_boundaries_require_a_chronological_pair(self):
        reference = {'onset': [100, 120], 'end': [1900, 1940],
                     'internal': {'end': [900, 940], 'resumed_onset': [1100, 1120]}}
        reversed_match = evaluate(reference, [{'onset': 1000, 'end': 1050}], 1000)
        self.assertEqual(reversed_match['pause_resume']['chronological_pairs'], [])
        self.assertEqual(reversed_match['pause_resume']['pair_status'], 'missing')
        valid = evaluate(reference, [{'onset': 110, 'end': 930},
                                    {'onset': 1110, 'end': 1920}], 1000)
        self.assertEqual(valid['pause_resume']['pair_status'], 'unique')
        self.assertEqual(valid['pause_resume']['chronological_pairs'],
                         [{'first_end_candidate': 0, 'resumed_onset_candidate': 0}])

    def test_nonfinite_and_nonnumeric_coordinates_rejected(self):
        for value in [float('nan'), float('inf'), True, '100']:
            with self.assertRaises(ValueError):
                evaluate({'onset': [100, 120], 'end': [900, 940]},
                         [{'onset': value, 'end': 930}], 1000)
            with self.assertRaises(ValueError):
                evaluate({'onset': [value, 120], 'end': [900, 940]}, [], 1000)

    def test_invalid_segments_rejected(self):
        with self.assertRaises(ValueError):
            evaluate({'onset': [100, 120], 'end': [900, 940]},
                     [{'onset': 500, 'end': 400}], 1000)

    def test_crop_resample_translation_is_exact(self):
        self.assertEqual(transform_band([15736, 15816], 12000, 2, 800), [8272, 8432])

    def test_controlled_variants_reproducible_and_stems_separate(self):
        caller = [1000, -1000] * 16000
        agent = [200, -200] * 16000
        first = build_variants(caller, agent, {'onset': [800, 900], 'end': [15000, 15100]})
        self.assertEqual(first, build_variants(caller, agent, {'onset': [800, 900], 'end': [15000, 15100]}))
        self.assertEqual(set(first), {'clean', 'quiet_tail', 'noise', 'echo', 'overlap', 'pause_resume'})
        self.assertEqual(first['overlap']['reference'], first['clean']['reference'])
        self.assertEqual(first['overlap']['agent_stem'], agent)
        self.assertEqual(first['pause_resume']['reference']['end'], [63000, 63100])
        self.assertNotEqual(first['noise']['pcm'], caller)


if __name__ == '__main__':
    unittest.main()
