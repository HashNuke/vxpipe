"""Small frozen-reference acoustic pilot; never infer labels from detector output."""
import argparse
import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'apps/vxpipe_call_engine/test/fixtures/speech/acoustic_acceptance'


def transform_band(band, crop_start, ratio, padding=0):
    return [(sample - crop_start) * ratio + padding for sample in band]


def _error(value, band, sample_rate):
    if value is None:
        return None
    lower, upper = [(value - bound) * 1000 / sample_rate for bound in reversed(band)]
    nearest = 0 if lower <= 0 <= upper else min(abs(lower), abs(upper))
    return {'signed_error_ms': [lower, upper],
            'absolute_error_ms': [nearest, max(abs(lower), abs(upper))]}


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _band(band):
    if (not isinstance(band, (list, tuple)) or len(band) != 2
            or not all(_number(x) for x in band) or not 0 <= band[0] <= band[1]):
        raise ValueError('finite ordered nonnegative reference band required')


def evaluate(reference, segments, sample_rate):
    """Score isolated clip boundaries with explicit matching and raw evidence.

    Entirely outside segments are reported separately, not silently discarded.
    Pause/resume matching retains all plausible candidates, never closest-only.
    """
    if not _number(sample_rate) or sample_rate <= 0:
        raise ValueError('positive finite sample rate required')
    for key in ('onset', 'end'):
        _band(reference[key])
    if reference['onset'][1] > reference['end'][0]:
        raise ValueError('reference onset must precede reference end')
    internal = reference.get('internal')
    if internal:
        for key in ('end', 'resumed_onset'):
            _band(internal[key])
        if not (reference['onset'][1] <= internal['end'][0]
                <= internal['end'][1] < internal['resumed_onset'][0]
                <= internal['resumed_onset'][1] <= reference['end'][0]):
            raise ValueError('pause/resume reference bands must be ordered')
    previous_end = -1
    for index, segment in enumerate(segments):
        onset, end = segment['onset'], segment['end']
        if not _number(onset) or onset < 0 or onset < previous_end:
            raise ValueError('finite ordered nonoverlapping segment onsets required')
        if end is None and index != len(segments) - 1:
            raise ValueError('only final segment may remain open')
        if end is not None and (not _number(end) or end < onset):
            raise ValueError('finite segment end must not precede onset')
        previous_end = onset if end is None else end
    before = [i for i, seg in enumerate(segments)
              if seg['end'] is not None and seg['end'] < reference['onset'][0]]
    after = [i for i, seg in enumerate(segments) if seg['onset'] > reference['end'][1]]
    eligible = [i for i in range(len(segments)) if i not in before and i not in after]
    onset = segments[eligible[0]]['onset'] if eligible else None
    end = segments[eligible[-1]]['end'] if eligible else None
    result = {'onset': _error(onset, reference['onset'], sample_rate),
              'end': _error(end, reference['end'], sample_rate),
              'incomplete_rate': int(onset is None or end is None),
              'detected_segment_count': len(segments),
              'internal_segment_count': max(0, len(eligible) - 1),
              'before_reference_segment_indices': before,
              'after_reference_segment_indices': after,
              'outer_matched_segment_indices': ([eligible[0], eligible[-1]] if eligible else []),
              'raw_segments': [dict(segment) for segment in segments],
              'reference_method': 'visually reviewed uncertainty bands; no listening',
              'matching': 'outermost segments intersecting the reference envelope; outside evidence retained',
              'scope': 'outer clip boundaries, not conversational-turn segmentation'}
    if internal:
        def candidates(key, band, lo, hi):
            found = [{'segment_index': i, 'sample': seg[key],
                      'error': _error(seg[key], band, sample_rate)}
                     for i, seg in enumerate(segments)
                     if seg[key] is not None and lo <= seg[key] <= hi]
            return {'status': 'missing' if not found else 'unique' if len(found) == 1 else 'ambiguous',
                    'candidate_window_samples': [lo, hi], 'candidates': found}
        result['pause_resume'] = {
            'first_end': candidates('end', internal['end'], reference['onset'][1],
                                    internal['resumed_onset'][0]),
            'resumed_onset': candidates('onset', internal['resumed_onset'], internal['end'][1],
                                        reference['end'][0])}
        pause = result['pause_resume']
        pairs = [{'first_end_candidate': i, 'resumed_onset_candidate': j}
                 for i, ending in enumerate(pause['first_end']['candidates'])
                 for j, resumed in enumerate(pause['resumed_onset']['candidates'])
                 if ending['segment_index'] < resumed['segment_index']
                 and ending['sample'] < resumed['sample']]
        pause['chronological_pairs'] = pairs
        pause['pair_status'] = 'missing' if not pairs else 'unique' if len(pairs) == 1 else 'ambiguous'
    return result


def _clip(value):
    return max(-32768, min(32767, round(value)))


def build_variants(caller, agent, reference):
    """Deterministic controlled conditions, not natural conversational captures."""
    variants = {}
    def add(name, pcm, ref=None, **details):
        variants[name] = {'pcm': pcm, 'reference': ref or reference, **details}
    add('clean', list(caller), transform={'kind': 'identity'})
    tail_start = max(reference['onset'][1], reference['end'][0] - 4000)
    quiet = [(_clip(value * .15) if i >= tail_start else value)
             for i, value in enumerate(caller)]
    add('quiet_tail', quiet, transform={'kind': 'gain', 'from_sample': tail_start, 'gain': .15})
    rng = random.Random(20261120)
    noise = [rng.randint(-300, 300) for _ in caller]
    add('noise', [_clip(a + b) for a, b in zip(caller, noise)],
        transform={'kind': 'uniform_noise', 'seed': 20261120, 'peak_pcm': 300})
    delay = 1600
    echo = [_clip(value + (.3 * caller[i-delay] if i >= delay else 0))
            for i, value in enumerate(caller)]
    add('echo', echo, transform={'kind': 'delayed_copy', 'delay_samples': delay, 'gain': .3,
                                'reference': 'direct caller stem excludes echo tail'})
    stem = list(agent[:len(caller)]) + [0] * max(0, len(caller) - len(agent))
    add('overlap', [_clip(a + .5 * b) for a, b in zip(caller, stem)], agent_stem=stem,
        transform={'kind': 'separate_voice_stem', 'gain': .5, 'offset_samples': 0,
                   'reference': 'caller only; overlapping other voice excluded'})
    offset = len(caller) + 16000
    resumed_ref = {'onset': reference['onset'], 'end': [x + offset for x in reference['end']],
                   'internal': {'end': reference['end'],
                                'resumed_onset': [x + offset for x in reference['onset']]}}
    add('pause_resume', list(caller) + [0] * 16000 + list(caller), resumed_ref,
        transform={'kind': 'repeat_after_pause', 'second_copy_offset_samples': offset,
                   'inserted_silence_samples': 16000,
                   'internal_reference': {'end': reference['end'],
                       'resumed_onset': [x + offset for x in reference['onset']]}})
    return variants


def _read(path):
    with wave.open(str(path)) as handle:
        if (handle.getframerate(), handle.getnchannels(), handle.getsampwidth()) != (8000, 1, 2):
            raise ValueError('expected mono 8kHz s16 WAV')
        raw = handle.readframes(handle.getnframes())
    return list(struct.unpack('<' + 'h' * (len(raw)//2), raw))


def _upsample(samples):
    # Linear 2x resampling: exact source indices map to even output indices.
    out = []
    for i, sample in enumerate(samples):
        out.extend((sample, round((sample + samples[min(i+1, len(samples)-1)]) / 2)))
    return out


def build(output):
    frozen_bytes = (FIXTURES / 'reference.json').read_bytes()
    expected_digest = (FIXTURES / 'reference.sha256').read_text().split()[0]
    if hashlib.sha256(frozen_bytes).hexdigest() != expected_digest:
        raise ValueError('frozen reference checksum mismatch')
    frozen = json.loads(frozen_bytes)
    output.mkdir(parents=True, exist_ok=True)
    clips = {}
    for entry in frozen['sources']:
        path = FIXTURES / entry['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('source checksum mismatch')
        samples = _read(path)
        lo, hi = entry['crop_samples']
        clips[entry['id']] = (_upsample(samples[lo:hi]),
            {key: transform_band(entry[key], lo, 2) for key in ('onset', 'end')})
    rows = []
    for ident, (caller, reference) in clips.items():
        other = next(value[0] for key, value in clips.items() if key != ident)
        for condition, variant in build_variants(caller, other, reference).items():
            raw = struct.pack('<' + 'h' * len(variant['pcm']), *variant.pop('pcm'))
            name = f'{ident}-{condition}.pcm'
            (output / name).write_bytes(raw)
            row = {'id': f'{ident}-{condition}', 'file': name, 'sample_rate': 16000,
                   'samples': len(raw)//2, 'sha256': hashlib.sha256(raw).hexdigest(), **variant}
            stem = row.pop('agent_stem', None)
            if stem is not None:
                data = struct.pack('<' + 'h' * len(stem), *stem)
                stem_name = f'{ident}-agent-stem.pcm'
                (output / stem_name).write_bytes(data)
                row['agent_stem'] = {'file': stem_name, 'sha256': hashlib.sha256(data).hexdigest(),
                                     'source_id': next(key for key in clips if key != ident)}
            rows.append(row)
    manifest = {'reference_sha256': hashlib.sha256(frozen_bytes).hexdigest(),
                'sample_rate': 16000, 'resampler': 'linear 2x; source indices map to even output indices',
                'cases': rows, 'claims': frozen['claims']}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = build(args.output)
    print(json.dumps({'cases': len(manifest['cases']), 'reference_sha256': manifest['reference_sha256']}))
