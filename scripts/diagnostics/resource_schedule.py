"""Bounded process samples on the external audio clock; no downstream pacing."""
from dataclasses import asdict
import time
import math
from measurement import begin_interval, read_process, summarize

PERIOD_NS = 100_000_000
MAX_BOUNDARY_LATENESS_NS = 2_000_000
TIMING_CONTRACT = 'boundary-2ms-no-skipped-slot-v1'
COLD_MAX_DURATION_NS = 45_000_000_000
COLD_MAX_START_NS = COLD_MAX_DURATION_NS - 20_000_000_000


class ResourceSchedule:
    def __init__(self, pid, *, start_offset_ns=0, reader=read_process,
                 begin=begin_interval, clock=time.monotonic_ns):
        if type(start_offset_ns) is not int or start_offset_ns < 0:
            raise ValueError('invalid measurement offset')
        self.initial = reader(pid)
        self.pid = pid
        self.reader, self.begin, self.clock = reader, begin, clock
        self.start_offset_ns = start_offset_ns
        self.samples, self.events = [], []
        self.started = False
        self.closed = False

    def start(self, start_ns, duration_ns):
        if (self.started or type(start_ns) is not int or type(duration_ns) is not int
                or not 0 <= self.start_offset_ns < duration_ns <= 32_000_000_000):
            raise ValueError('invalid resource interval')
        self.started = True
        self.start_ns = start_ns + self.start_offset_ns
        self.end_ns = start_ns + duration_ns
        self.next_ns = self.start_ns

    def start_cold(self, start_ns):
        if self.start_offset_ns != 0:
            raise ValueError('cold interval must start before preparation')
        self.start(start_ns, 32_000_000_000)
        self.end_ns = start_ns + COLD_MAX_DURATION_NS
        self.cold = True
        self.preparation = None

    def cold_ready(self, ready_ns):
        if (not getattr(self, 'cold', False) or self.preparation is not None
                or type(ready_ns) is not int
                or not 0 <= ready_ns - self.start_ns <= 15_000_000_000
                or not self.samples or self.closed):
            raise ValueError('invalid or late cold readiness')
        sample = self.reader(self.pid)
        if (sample.pid, sample.start_ticks) != (self.pid, self.initial.start_ticks):
            raise ValueError('resource target replaced at readiness')
        self.preparation = dict(preparation_duration_ns=ready_ns - self.start_ns,
                                preparation_cpu_seconds=sample.cpu_seconds - self.samples[0].cpu_seconds,
                                ready_at_ns=ready_ns, preparation_sample=asdict(sample))

    def cold_audio_start(self, start_ns):
        if (not getattr(self, 'cold', False) or self.preparation is None
                or not self.preparation['ready_at_ns'] <= start_ns <= self.start_ns + COLD_MAX_START_NS):
            raise ValueError('invalid cold audio start')
        self.audio_start_ns = start_ns
        self.end_ns = start_ns + 20_000_000_000

    def advance(self, deadline_ns, *, wait, emit):
        if not self.started:
            raise ValueError('resource interval not started')
        while not self.closed and self.next_ns <= deadline_ns:
            wait(self.next_ns)
            read_started = self.clock()
            read_cpu_started = time.thread_time_ns()
            sample = (self.begin(self.pid, expected_start_ticks=self.initial.start_ticks)
                      if not self.samples else self.reader(self.pid))
            read_cpu_ns = time.thread_time_ns() - read_cpu_started
            read_finished = self.clock()
            if (sample.pid, sample.start_ticks) != (self.pid, self.initial.start_ticks):
                raise ValueError('resource target replaced')
            event = dict(deadline_ns=self.next_ns, read_started_ns=read_started,
                         read_finished_ns=read_finished, read_cpu_ns=read_cpu_ns,
                         sample=asdict(sample))
            self.samples.append(sample)
            self.events.append(event)
            emit(event)
            if self.next_ns == self.end_ns:
                self.closed = True
            else:
                self.next_ns = min(self.next_ns + PERIOD_NS, self.end_ns)

    def report(self):
        if not self.closed or (getattr(self, 'cold', False) and not hasattr(self, 'audio_start_ns')):
            raise ValueError('incomplete resource interval')
        lateness = [max(0, e['read_finished_ns'] - e['deadline_ns']) for e in self.events]
        gaps = [b['read_finished_ns'] - a['read_finished_ns']
                for a, b in zip(self.events, self.events[1:])]
        valid_reads = all(e['deadline_ns'] <= e['read_started_ns'] <= e['read_finished_ns']
                          for e in self.events)
        preparation = getattr(self, 'preparation', None)
        return dict(**(dict(preparation, audio_start_ns=self.audio_start_ns) if preparation else {}),
                    pid=self.pid, start_ticks=self.initial.start_ticks, timing_contract=TIMING_CONTRACT,
                    scheduled_start_ns=self.start_ns, scheduled_end_ns=self.end_ns,
                    start_lateness_ns=lateness[0], end_lateness_ns=lateness[-1],
                    maximum_lateness_ns=max(lateness), maximum_sample_gap_ns=max(gaps),
                    timing_valid=valid_reads and max(lateness[0], lateness[-1]) <= MAX_BOUNDARY_LATENESS_NS
                    and all(event['read_finished_ns'] < following['deadline_ns']
                            for event, following in zip(self.events[1:-1], self.events[2:])),
                    summary=summarize_resources(self.samples, None if preparation is None else preparation['preparation_sample']))


def summarize_resources(samples, preparation_sample=None):
    """Periodic endpoints define duration; the extra readiness read contributes peaks."""
    summary = summarize(samples)
    if preparation_sample is None:
        return summary
    from measurement import ProcessSample
    ready = ProcessSample(**preparation_sample)
    if (ready.interval_start is not False
            or (ready.pid, ready.start_ticks) != (samples[0].pid, samples[0].start_ticks)
            or any(type(value) is not int or value <= 0 for value in (ready.pid, ready.start_ticks, ready.threads))
            or any(type(value) not in (int, float) or not math.isfinite(value) or value < 0
                   for value in (ready.at_seconds, ready.cpu_seconds, ready.rss_kib, ready.high_water_kib))
            or ready.high_water_kib < ready.rss_kib
            or not samples[0].at_seconds <= ready.at_seconds <= samples[-1].at_seconds):
        raise ValueError('invalid preparation resource sample')
    before = max((sample for sample in samples if sample.at_seconds <= ready.at_seconds), key=lambda sample: sample.at_seconds)
    after = min((sample for sample in samples if sample.at_seconds >= ready.at_seconds), key=lambda sample: sample.at_seconds)
    if not before.cpu_seconds <= ready.cpu_seconds <= after.cpu_seconds:
        raise ValueError('nonmonotonic preparation CPU sample')
    summary.update(peak_sampled_rss_kib=max(summary['peak_sampled_rss_kib'], ready.rss_kib),
                   process_high_water_kib=max(summary['process_high_water_kib'], ready.high_water_kib),
                   maximum_threads=max(summary['maximum_threads'], ready.threads))
    return summary
