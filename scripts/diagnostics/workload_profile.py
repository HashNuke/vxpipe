"""Fixed diagnostic audio windows; no readiness-dependent pacing."""
from dataclasses import dataclass

PERIOD_NS = 32_000_000


@dataclass(frozen=True)
class WorkloadProfile:
    name: str
    duration_ns: int
    measurement_start_ns: int
    cadence_frames: int
    leading_frames: int
    speech_frames: int

    @property
    def maximum_frames(self):
        return (self.duration_ns + PERIOD_NS - 1) // PERIOD_NS

    def frame_count(self, index, inputs):
        if type(inputs) is not int or not 1 <= inputs <= 16 or type(index) is not int or not 0 <= index < inputs:
            raise ValueError('invalid input shape')
        phase = PERIOD_NS * index // inputs
        return (self.duration_ns - 1 - phase) // PERIOD_NS + 1

    def settlements(self, index, inputs, humans):
        count = self.frame_count(index, inputs)
        if type(humans) is not int or humans not in (1, 2) or inputs % humans:
            raise ValueError('invalid room shape')
        rooms = inputs // humans
        slot = (index % humans) * rooms + index // humans
        first = self.leading_frames + self.cadence_frames * (slot + 1) // inputs
        return list(range(first, count + 1, self.cadence_frames))


def profile(name):
    if name == 'smoke':
        return WorkloadProfile(name, 6_144_000_000, 0, 64, 64, 32)
    if name == 'warm':
        return WorkloadProfile(name, 25_000_000_000, 5_000_000_000, 60, 64, 24)
    raise ValueError('unknown workload profile')
