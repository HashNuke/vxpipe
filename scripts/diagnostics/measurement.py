"""Linux process resource accounting for isolated diagnostic measurement VMs.

This helper validates resource samples only. Passing its CPU/RSS budgets does not
establish workload correctness, coverage, latency, generator timing or readiness.
"""
from contextlib import ExitStack
from dataclasses import dataclass, replace
import math
import os
from pathlib import Path
import time


@dataclass(frozen=True)
class ProcessSample:
    pid: int
    start_ticks: int
    at_seconds: float
    cpu_seconds: float
    rss_kib: int
    high_water_kib: int
    threads: int
    interval_start: bool = False


def _stat_text(text, pid):
    prefix, fields = text.rsplit(') ', 1)
    if int(prefix.split(' (', 1)[0]) != pid:
        raise ValueError('process identity mismatch')
    fields = fields.split()
    return int(fields[19]), int(fields[11]) + int(fields[12])


def read_process(pid, *, proc_root=Path('/proc'), ticks_per_second=None, clock=time.monotonic, _files=None):
    """Read aggregate process CPU ticks and RSS, including native allocations."""
    if type(pid) is not int or pid <= 0:
        raise ValueError('invalid process id')
    ticks = ticks_per_second if ticks_per_second is not None else os.sysconf('SC_CLK_TCK')
    if not math.isfinite(ticks) or ticks <= 0:
        raise ValueError('invalid clock tick rate')
    path = proc_root / str(pid)
    def read_text(name):
        if _files is None:
            return (path / name).read_text()
        file = _files[name]
        file.seek(0)
        return file.read()
    identity, cpu = _stat_text(read_text('stat'), pid)
    status = {}
    for line in read_text('status').splitlines():
        key, _, value = line.partition(':')
        if key in ('VmRSS', 'VmHWM', 'Threads'):
            values = value.split()
            if key != 'Threads' and values[1:] != ['kB']:
                raise ValueError('unexpected resident-memory units')
            status[key] = int(values[0])
    # A recycled PID between the stat and status reads cannot form one sample.
    if _stat_text(read_text('stat'), pid)[0] != identity:
        raise ValueError('process replaced during sampling')
    return ProcessSample(pid, identity, clock(), cpu / ticks,
                         status['VmRSS'], status['VmHWM'], status['Threads'])


class PinnedProcessReader:
    """Reuse owned proc descriptors; sample values are reread, never cached."""
    def __init__(self, pid, *, proc_root=Path('/proc'), **options):
        initial = read_process(pid, proc_root=proc_root, **options)
        self.pid, self.start_ticks, self.options = pid, initial.start_ticks, options
        self.stack = ExitStack()
        try:
            self.files = {name: self.stack.enter_context((proc_root / str(pid) / name).open())
                          for name in ('stat', 'status')}
            self(pid)
        except BaseException:
            self.stack.close()
            raise

    def __call__(self, pid):
        if pid != self.pid:
            raise ValueError('different resource target')
        sample = read_process(pid, _files=self.files, **self.options)
        if sample.start_ticks != self.start_ticks:
            raise ValueError('resource target replaced')
        return sample

    def __enter__(self):
        return self

    def __exit__(self, *_exception):
        self.stack.close()


def begin_interval(pid, *, expected_start_ticks=None, **options):
    """Reset only the isolated target's RSS high-water counter at the phase boundary.

    Call before room preparation for cold runs and after warm-up for warm runs.
    Missing procfs support/permission fails the run instead of using lifetime HWM.
    """
    before = read_process(pid, **options)
    if expected_start_ticks is not None and before.start_ticks != expected_start_ticks:
        raise ValueError('process replaced before interval reset')
    root = options.get('proc_root', Path('/proc'))
    # Open without truncation before the second identity check. procfs writes
    # resolve the task from this file's inode, not a later lookup of the PID.
    descriptor = os.open(root / str(pid) / 'clear_refs', os.O_WRONLY)
    with os.fdopen(descriptor, 'w') as reset:
        current = read_process(pid, **options)
        if current.start_ticks != before.start_ticks:
            raise ValueError('process replaced before interval reset')
        reset.write('5\n')
        reset.flush()
        first = read_process(pid, **options)
    if before.start_ticks != first.start_ticks:
        raise ValueError('process replaced at interval boundary')
    return replace(first, interval_start=True)



def summarize(samples):
    """Require one scoped interval; retain sampled RSS and OS high water separately."""
    if len(samples) < 2 or not samples[0].interval_start:
        raise ValueError('missing scoped measurement interval')
    first = samples[0]
    previous = None
    for sample in samples:
        numbers = (sample.at_seconds, sample.cpu_seconds, sample.rss_kib,
                   sample.high_water_kib, sample.threads)
        if not all(math.isfinite(value) and value >= 0 for value in numbers):
            raise ValueError('invalid resource sample')
        if sample.threads < 1 or sample.high_water_kib < sample.rss_kib:
            raise ValueError('invalid resident-memory or thread counters')
        if (sample.pid, sample.start_ticks) != (first.pid, first.start_ticks):
            raise ValueError('process identity changed')
        if previous and (sample.interval_start or sample.at_seconds <= previous.at_seconds
                         or sample.cpu_seconds < previous.cpu_seconds):
            raise ValueError('nonmonotonic resource samples')
        previous = sample
    # Linux reports max(stored hiwater, current approximate RSS); retain the
    # largest observation even if a later reported VmHWM dips slightly.
    elapsed = samples[-1].at_seconds - first.at_seconds
    cpu = samples[-1].cpu_seconds - first.cpu_seconds
    return dict(sample_count=len(samples), duration_seconds=elapsed, cpu_seconds=cpu,
                cpu_cores=cpu / elapsed,
                peak_sampled_rss_kib=max(s.rss_kib for s in samples),
                process_high_water_kib=max(s.high_water_kib for s in samples),
                maximum_threads=max(s.threads for s in samples))


def compare_resources(disabled, enabled, *, mode, inputs):
    """Apply the predeclared resource budgets; every matched pair must pass."""
    if mode not in ('fallback', 'reuse') or type(inputs) is not int or not 1 <= inputs <= 16:
        raise ValueError('unsupported measurement mode or capacity')
    cpu_budget = .05 + .03 * inputs if mode == 'fallback' else .02 + .005 * inputs
    rss_budget = (128 + 8 * inputs) * 1024
    for summary in (disabled, enabled):
        for key in ('cpu_cores', 'process_high_water_kib'):
            if not math.isfinite(summary[key]) or summary[key] < 0:
                raise ValueError('invalid resource summary')
    cpu_delta = enabled['cpu_cores'] - disabled['cpu_cores']
    rss_delta = enabled['process_high_water_kib'] - disabled['process_high_water_kib']
    # Division/subtraction can put an exact boundary a few representable floats
    # above it. Permit arithmetic roundoff only, never a workload-level margin.
    cpu_roundoff = 4 * max(math.ulp(value) for value in
                           (enabled['cpu_cores'], disabled['cpu_cores'], cpu_budget))
    cpu_passes = cpu_delta <= cpu_budget or math.isclose(
        cpu_delta, cpu_budget, rel_tol=0.0, abs_tol=cpu_roundoff)
    return dict(cpu_delta_cores=cpu_delta, cpu_budget_cores=cpu_budget,
                rss_delta_kib=rss_delta, rss_budget_kib=rss_budget,
                cpu_roundoff_cores=cpu_roundoff,
                passes=cpu_passes and rss_delta <= rss_budget)
