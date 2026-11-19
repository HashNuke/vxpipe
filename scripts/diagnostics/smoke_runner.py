"""Run the four configured Silero smoke cases with enforced CPU isolation.

This is a watchdog/functional smoke runner, not paired performance acceptance.
It creates only uniquely named transient units and requires noninteractive sudo
for its own system scope. The workload itself runs as the invoking normal user.
"""
import argparse
import hashlib
from dataclasses import asdict
import json
import os
from pathlib import Path
import pwd
import re
import signal
import subprocess
import time
import uuid

from measurement import ProcessSample, read_process, summarize

ROOT = Path(__file__).resolve().parents[2]
MARKER = 'DIAGNOSTIC_GENERATOR_UNIT '
SMOKE_MARKER = 'DIAGNOSTIC_EXTERNAL_SMOKE '
RESOURCE_MARKER = 'DIAGNOSTIC_RESOURCE_SAMPLE '


class OwnedUnits:
    def __init__(self, run_id):
        if not re.fullmatch(r'[0-9a-f]{32}', run_id):
            raise ValueError('invalid run identity')
        self.run_id = run_id
        self.scope = f'vxpipe-diagnostic-smoke-{run_id}.scope'
        self.generators = set()
        self.pending_databases = set()

    def observe(self, line):
        for marker in ('DIAGNOSTIC_DATABASE_RESERVED ', 'DIAGNOSTIC_DATABASE_DROPPED '):
            if marker in line:
                database = line.split(marker, 1)[1].strip()
                if not re.fullmatch(rf'vxdiag_{self.run_id}_[0-9a-f]{{8}}', database):
                    raise ValueError('unowned measurement database in workload output')
                if marker == 'DIAGNOSTIC_DATABASE_RESERVED ':
                    self.pending_databases.add(database)
                elif database in self.pending_databases:
                    self.pending_databases.remove(database)
                else:
                    raise ValueError('unregistered database drop acknowledgement')
                return
        if MARKER not in line:
            return
        unit = line.split(MARKER, 1)[1].strip()
        pattern = (rf'vxpipe-diagnostic-generator-{self.run_id}-'
                   r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.service')
        if not re.fullmatch(pattern, unit):
            raise ValueError('unowned generator unit in workload output')
        self.generators.add(unit)


def parse_cpu_mask(text):
    result = set()
    for part in text.split(','):
        bounds = part.split('-')
        if len(bounds) not in (1, 2):
            raise ValueError('invalid CPU mask')
        low, high = int(bounds[0]), int(bounds[-1])
        if not 0 <= low <= high < 4096:
            raise ValueError('invalid CPU mask')
        result.update(range(low, high + 1))
    return result


def violation(beams, *, available_kib, elapsed):
    if sum(beam['rss_kib'] for beam in beams) > 1024 * 1024:
        return 'VM RSS exceeds 1024 MiB'
    if available_kib < 768 * 1024:
        return 'host available memory below 768 MiB'
    if elapsed > 300:
        return '300 second watchdog deadline'
    if len(beams) > 1:
        return 'more than one measured VM'
    for beam in beams:
        masks = beam['thread_cpu_masks']
        if not masks or any(not parse_cpu_mask(mask) <= {0, 1} for mask in masks):
            return 'native thread outside enforced CPUs 0-1'
    return None


def available_memory():
    line = next(line for line in Path('/proc/meminfo').read_text().splitlines()
                if line.startswith('MemAvailable:'))
    return int(line.split()[1])


def descendants(pid):
    result = [pid]
    try:
        children = Path(f'/proc/{pid}/task/{pid}/children').read_text().split()
    except FileNotFoundError:
        return result
    for child in children:
        result.extend(descendants(int(child)))
    return result


def snapshot(pid):
    beams = []
    for child in descendants(pid):
        path = Path(f'/proc/{child}')
        try:
            if (path / 'comm').read_text().strip() != 'beam.smp':
                continue
            state = next(line for line in (path / 'status').read_text().splitlines()
                         if line.startswith('State:'))
            if state.split()[1] in ('Z', 'X'):
                continue
            sample = read_process(child)
            masks = set()
            for thread in (path / 'task').glob('*/status'):
                try:
                    masks.add(next(line.split(':', 1)[1].strip()
                                   for line in thread.read_text().splitlines()
                                   if line.startswith('Cpus_allowed_list:')))
                except FileNotFoundError:
                    pass
            if read_process(child).start_ticks != sample.start_ticks:
                raise ValueError('measured process replaced during sampling')
            beams.append(dict(asdict(sample), thread_cpu_masks=sorted(masks)))
        except FileNotFoundError:
            continue
    return dict(available_kib=available_memory(), beams=beams)


def stop_unit(unit, *, system=False):
    prefix = ['sudo', '-n', 'systemctl'] if system else ['systemctl', '--user']
    result = subprocess.run(prefix + ['stop', unit], capture_output=True, text=True, timeout=5)
    if result.returncode:
        state = subprocess.run(prefix + ['show', unit, '-p', 'ActiveState', '--value'],
                               capture_output=True, text=True, timeout=5)
        if state.stdout.strip() not in ('inactive', 'failed'):
            raise RuntimeError('could not stop owned transient unit')


def resource_complete(report, samples):
    try:
        interval = report['generator']['resource_interval']
        events = report['resource_samples']
        if (not isinstance(interval, dict) or len(events) != 63
                or interval.get('timing_contract') != 'boundary-2ms-no-skipped-slot-v1'):
            return False
        start, end = interval['scheduled_start_ns'], interval['scheduled_end_ns']
        if type(start) is not int or type(end) is not int or end - start != 6_144_000_000:
            return False
        if [e['deadline_ns'] for e in events] != list(range(start, end, 100_000_000)) + [end]:
            return False
        raw = [ProcessSample(**e['sample']) for e in events]
        summary = summarize(raw)
        identities = {(b['pid'], b['start_ticks']) for s in samples for b in s['beams']}
        identity = (interval['pid'], interval['start_ticks'])
        if identity not in identities or any((s.pid, s.start_ticks) != identity for s in raw):
            return False
        for event, sample in zip(events, raw):
            before, after = event['read_started_ns'], event['read_finished_ns']
            if (type(before) is not int or type(after) is not int
                    or not event['deadline_ns'] <= before <= after
                    or not before - 1 <= round(sample.at_seconds * 1e9) <= after + 1):
                return False
        lateness = [e['read_finished_ns'] - e['deadline_ns'] for e in events]
        gaps = [b['read_finished_ns'] - a['read_finished_ns'] for a, b in zip(events, events[1:])]
        return (interval['timing_valid'] is True and summary == interval['summary']
                and max(lateness[0], lateness[-1]) <= 2_000_000
                and all(e['read_finished_ns'] < following['deadline_ns']
                        for e, following in zip(events[1:-1], events[2:]))
                and 6.140 <= summary['duration_seconds'] <= 6.148
                and interval['start_lateness_ns'] == lateness[0]
                and interval['end_lateness_ns'] == lateness[-1]
                and interval['maximum_lateness_ns'] == max(lateness)
                and interval['maximum_sample_gap_ns'] == max(gaps))
    except (KeyError, TypeError, ValueError, OverflowError):
        return False


def smoke_complete(reports, samples, *, committed_writes=False, rooms=1, inputs_per_room=1,
                   sample_resources=False):
    expected = {(False, False), (False, True), (True, False), (True, True)}
    if len(reports) != 4 or {(r['operational_vad'], r['collection']) for r in reports} != expected:
        return False
    if not any(sample['beams'] for sample in samples):
        return False
    if sample_resources:
        if not all(resource_complete(r, samples) for r in reports):
            return False
        for previous, current in zip(reports, reports[1:]):
            if (current['generator']['resource_interval']['scheduled_start_ns'] <=
                    previous['generator']['resource_interval']['scheduled_end_ns']
                    or current['resource_samples'][0]['sample']['cpu_seconds'] <
                    previous['resource_samples'][-1]['sample']['cpu_seconds']):
                return False
    if committed_writes and any(r.get('persistence') != 'committed' or
                                r.get('database_pool_size') != 10 for r in reports):
        return False
    if any(r.get('rooms', 1) != rooms or r.get('inputs_per_room', 1) != inputs_per_room
           for r in reports):
        return False
    return all(type(r['operational_vad']) is bool and type(r['collection']) is bool and
               r['generator']['frames_sent'] == 192 * rooms * inputs_per_room and
               type(r['generator']['p95_lateness_ns']) is int and
               0 <= r['generator']['p95_lateness_ns'] <= 2_000_000 and
               r['generator']['elapsed_ns'] >= 6_144_000_000 for r in reports)


def watch(process, owned, log_path, *, sample=snapshot, clock=time.monotonic, sleep=time.sleep,
          committed_writes=False, rooms=1, inputs_per_room=1, sample_resources=False):
    samples, reports, cleanup_errors = [], [], []
    resource_samples, current_resources = [], []
    abort, pending = None, ''
    identity = None
    start = clock()
    reader = log_path.open()

    def consume():
        nonlocal pending, abort, current_resources
        pending += reader.read()
        while '\n' in pending:
            line, pending = pending.split('\n', 1)
            try:
                owned.observe(line)
                if MARKER in line:
                    current_resources = []
                if RESOURCE_MARKER in line:
                    event = json.loads(line.split(RESOURCE_MARKER, 1)[1])
                    if not isinstance(event, dict) or len(resource_samples) >= 252:
                        raise ValueError('invalid or excessive resource samples')
                    resource_samples.append(event)
                    current_resources.append(event)
                if SMOKE_MARKER in line:
                    report = json.loads(line.split(SMOKE_MARKER, 1)[1])
                    report['resource_samples'] = list(current_resources)
                    reports.append(report)
                    current_resources = []
            except (ValueError, TypeError) as error:
                # Keep scanning so invalid output cannot hide later owned units.
                abort = abort or type(error).__name__ + ': invalid workload output'


    try:
        while process.poll() is None:
            consume()
            if abort:
                break
            observed = dict(sample(process.pid), seconds=clock() - start)
            samples.append(observed)
            for beam in observed['beams']:
                current = (beam['pid'], beam['start_ticks'])
                if identity is not None and current != identity:
                    raise ValueError('measured process identity changed')
                identity = current
            abort = violation(observed['beams'], available_kib=observed['available_kib'],
                              elapsed=observed['seconds'])
            if abort:
                break
            sleep(.1)
    except (Exception, KeyboardInterrupt) as error:
        abort = type(error).__name__ + ': ' + str(error)
    finally:
        # Stop future producers first, then read all registered owned unit names.
        try:
            stop_unit(owned.scope, system=True)
        except Exception as error:
            cleanup_errors.append(type(error).__name__ + ': scope cleanup failed')
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            # The process group was created by this runner; never target a name/PID
            # supplied by workload output. A live child PID cannot yet be reused.
            try:
                subprocess.run(['sudo', '-n', 'kill', '-KILL', '--', f'-{process.pid}'],
                               capture_output=True, timeout=5)
                process.wait(timeout=5)
                cleanup_errors.append('launcher required process-group kill')
            except Exception:
                cleanup_errors.append('launcher could not be reaped after owned-scope cleanup')
        except Exception:
            cleanup_errors.append('launcher wait failed')
        try:
            consume()
        except Exception as error:
            abort = abort or type(error).__name__ + ': invalid final output'
        reader.close()
        for unit in sorted(owned.generators):
            try:
                stop_unit(unit)
            except Exception as error:
                cleanup_errors.append(type(error).__name__ + ': generator cleanup failed')
    try:
        complete = smoke_complete(reports, samples, committed_writes=committed_writes, rooms=rooms,
                                  inputs_per_room=inputs_per_room, sample_resources=sample_resources)
    except (KeyError, TypeError, ValueError):
        complete = False
    return dict(run_id=owned.run_id, exit_code=process.returncode, abort=abort,
                cleanup_errors=cleanup_errors, retained_databases=sorted(owned.pending_databases),
                samples=samples, smoke_reports=reports, resource_samples=resource_samples,
                completed=process.returncode == 0 and abort is None and not cleanup_errors and
                not owned.pending_databases and complete)


def provenance():
    paths = ['scripts/diagnostics/smoke_runner.py', 'scripts/diagnostics/measurement.py', 'scripts/diagnostics/resource_schedule.py',
             'scripts/diagnostics/pcm_generator.py', 'mix.lock',
             'apps/vxpipe_console/test/integration/configured_latency_diagnostics_test.exs',
             'apps/vxpipe_console/test/support/diagnostics_database.ex',
             'apps/vxpipe_console/test/support/diagnostics_schedule.ex',
             'apps/vxpipe_console/test/support/speech_connection.ex',
             'apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/silero/model.ex',
             'apps/vxpipe_call_engine/priv/speech/silero_v6.2.3.onnx']
    return dict(
        source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                              text=True, timeout=5).strip(),
        worktree_dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT,
                                                   text=True, timeout=5).strip()),
        file_sha256={path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path, help='new directory; never overwrite evidence')
    parser.add_argument('--committed-writes', action='store_true',
                        help='use a fresh migrated database and real commits for each case')
    parser.add_argument('--rooms', type=int, choices=range(1, 17), default=1,
                        help='concurrent rooms (total human inputs must be at most 16)')
    parser.add_argument('--inputs-per-room', type=int, choices=(1, 2), default=1)
    parser.add_argument('--sample-resources', action='store_true', help='sample the audio-only VM interval on the generator clock')
    args = parser.parse_args()
    if args.rooms * args.inputs_per_room > 16:
        parser.error('at most 16 total human STT inputs')
    if os.getuid() == 0:
        parser.error('invoke as the checkout user, not root')
    if available_memory() < 1536 * 1024:
        parser.error('need at least 1536 MiB available host memory')
    subprocess.run(['sudo', '-n', 'true'], check=True, timeout=5)
    args.output.mkdir(parents=True, exist_ok=False)
    source = provenance()
    owned = OwnedUnits(uuid.uuid4().hex)
    username = pwd.getpwuid(os.getuid()).pw_name
    environment = [key + '=' + os.environ[key] for key in
                   ('PATH', 'MIX_HOME', 'HEX_HOME', 'XDG_RUNTIME_DIR') if key in os.environ]
    command = ['sudo', '-n', 'systemd-run', '--quiet', '--scope', '--collect',
               '--unit=' + owned.scope, '--property=AllowedCPUs=0,1',
               '--property=RuntimeMaxSec=300', '--property=TimeoutStopSec=2', '--',
               'runuser', '-u', username, '--', 'env', *environment,
               'ERL_FLAGS=+S 2:2 +SDcpu 1 +SDio 1 +A 2',
               'VXPIPE_DIAGNOSTIC_GENERATOR_CPUS=2,3', 'VXPIPE_DIAGNOSTIC_GENERATOR_SYSTEMD=1',
               'VXPIPE_DIAGNOSTIC_RUN_ID=' + owned.run_id,
               'VXPIPE_DIAGNOSTIC_ROOMS=' + str(args.rooms),
               'VXPIPE_DIAGNOSTIC_INPUTS_PER_ROOM=' + str(args.inputs_per_room),
               'VXPIPE_DIAGNOSTIC_RESOURCE_SAMPLES=' + ('1' if args.sample_resources else '0'),
               'VXPIPE_DIAGNOSTIC_COMMITTED_WRITES=' + ('1' if args.committed_writes else '0'),
               'mix', 'test', 'test/integration/configured_latency_diagnostics_test.exs',
               '--only', 'external_pcm', '--seed', '0', '--max-cases', '1']
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt('runner interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    log_path = args.output / 'workload.log'
    with log_path.open('w') as log:
        process = subprocess.Popen(command, cwd=ROOT / 'apps/vxpipe_console',
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        report = watch(process, owned, log_path, committed_writes=args.committed_writes,
                       rooms=args.rooms, inputs_per_room=args.inputs_per_room,
                       sample_resources=args.sample_resources)
    report['provenance'] = source
    report['scope'] = 'functional smoke watchdog; not paired performance acceptance'
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('run_id', 'completed', 'exit_code', 'abort', 'cleanup_errors', 'retained_databases')}))
    raise SystemExit(0 if report['completed'] else 1)


if __name__ == '__main__':
    main()
