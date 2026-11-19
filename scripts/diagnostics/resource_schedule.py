"""Bounded process samples on the external audio clock; no downstream pacing."""
from dataclasses import asdict
import time
from measurement import begin_interval, read_process, summarize

PERIOD_NS = 100_000_000
MAX_BOUNDARY_LATENESS_NS = 2_000_000
TIMING_CONTRACT = 'boundary-2ms-no-skipped-slot-v1'


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
        if not self.closed:
            raise ValueError('incomplete resource interval')
        lateness = [max(0, e['read_finished_ns'] - e['deadline_ns']) for e in self.events]
        gaps = [b['read_finished_ns'] - a['read_finished_ns']
                for a, b in zip(self.events, self.events[1:])]
        valid_reads = all(e['deadline_ns'] <= e['read_started_ns'] <= e['read_finished_ns']
                          for e in self.events)
        return dict(pid=self.pid, start_ticks=self.initial.start_ticks, timing_contract=TIMING_CONTRACT,
                    scheduled_start_ns=self.start_ns, scheduled_end_ns=self.end_ns,
                    start_lateness_ns=lateness[0], end_lateness_ns=lateness[-1],
                    maximum_lateness_ns=max(lateness), maximum_sample_gap_ns=max(gaps),
                    timing_valid=valid_reads and max(lateness[0], lateness[-1]) <= MAX_BOUNDARY_LATENESS_NS
                    and all(event['read_finished_ns'] < following['deadline_ns']
                            for event, following in zip(self.events[1:-1], self.events[2:])),
                    summary=summarize(self.samples))
