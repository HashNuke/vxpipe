# Morse audio providers

## Scope and baseline

Milestone 3 adds opt-in local MorseCodeSTT and MorseCodeTTS implementations through the existing
speech capability contracts. It must preserve the room, turn, output-sink, queue, interruption
and provider-registry boundaries; it is not ordinary-speech recognition and does not change the
default hosted providers. The starting tree has provider-neutral capability processes, but their
provider callbacks assume remote-style connection data. The smallest likely adaptation is to let
an in-process transport receive structured local connection data rather than inventing a URL.

## Normative reference check

The in-force ITU-R M.1677-1 recommendation was checked before fixtures were written. Annex 1
defines the International Morse alphabet and specifies a dash as three dot units, one unit between
marks in a character, three units between characters, and seven units between words. The initial
implementation includes the recommendation's ASCII letters, figures, and directly representable
punctuation. It deliberately uses a separate 14-unit local end gap because the ITU word spacing
does not define an application utterance boundary.

The deterministic PCM defaults are 16 kHz, one signed little-endian 16-bit channel, a 700 Hz tone,
60 ms dot units and amplitude 4096 (one eighth of full scale). Detection uses 10 ms analysis
windows, a bounded threshold and a 100 Hz frequency tolerance. Configuration caps text at 256
bytes, encoded audio at 8 MiB and one undecided utterance at 60 seconds; configured maxima are
themselves bounded.

## Checkpoint 1: independent codec foundation

The first test file defined two independent expectations before any codec module existed:

- normalized `ET A` must produce literal tone/silence runs with ITU spacing and the local end gap;
- a hand-authored square-wave `SOS 2` signal must decode after being split repeatedly at odd byte
  boundaries, including in the middle of a PCM sample.

The red run reported both codec modules missing. The implementation added separate alphabet,
configuration, encoder and incremental decoder responsibilities. The encoder renders sine PCM;
the reference fixture renders square PCM from a literal signal plan, so encoder and decoder bugs
cannot validate each other. The decoder holds at most one partial analysis window plus bounded
utterance state, rejects a wrong tone/timing, and supports an explicit flush for the final tail.

The green focused command passes `2 tests, 0 failures`. Its first pass exposed a default-argument
compiler warning in `Config.new/1`; a function header removed that warning, and
`mix compile --warnings-as-errors` from the owning child now passes. Full alphabet, invalid input,
size, flush, silence and tolerance tests remain before transport integration. The complete owning
child suite passes `119 tests, 0 failures (1 excluded)`.
