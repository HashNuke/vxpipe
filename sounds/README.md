# Café waiting music and phone ring

Six original **9-second** music loops, synthesized in [cafe.ck](cafe.ck), plus
a phone ringtone in [phone-ring.ck](phone-ring.ck). Everything uses stock
ChucK. Each WAV is stereo, 48 kHz, 16-bit PCM.

| File | Character |
| --- | --- |
| [cafe-keys.wav](cafe-keys.wav) | Warm electric piano, spacious melody, round bass, very light brushes. |
| [cafe-bossa.wav](cafe-bossa.wav) | Nylon-like plucked chords, syncopated bass, shakers, and a piano melody. |
| [cafe-lofi.wav](cafe-lofi.wav) | Mellow jazz chords, swung shakers, soft kick, and brushed half-time backbeat. |
| [cafe-mallets.wav](cafe-mallets.wav) | Soft vibraphone-like melody, plucked chords, and light brushes in F major. |
| [cafe-swing.wav](cafe-swing.wav) | Electric-piano jazz trio, walking bass, and brushed swing in E-flat major. |
| [cafe-ambient.wav](cafe-ambient.wav) | Dreamy keys over slow, warm pads, with no drums. |

Start with **bossa** for a café feel, or **keys** for quieter waiting music.
The first three use a Cmaj9 → Am9 → Dm9 → G13 turnaround over four bars at
106⅔ BPM; the lo-fi backbeat feels like half that tempo. Mallets and swing
transpose that turnaround into F and E-flat. Ambient uses two slow Amaj9 /
Dmaj9 colors over the same nine-second cycle.

From the repository root, play continuously (Ctrl-C stops):

```sh
chuck assets/cafe.ck:bossa
chuck assets/cafe.ck:keys
chuck assets/cafe.ck:lofi
chuck assets/cafe.ck:mallets
chuck assets/cafe.ck:swing
chuck assets/cafe.ck:ambient
```

Render the WAVs without playing through the speakers:

```sh
chuck --silent --srate:48000 assets/cafe.ck:keys:render
chuck --silent --srate:48000 assets/cafe.ck:bossa:render
chuck --silent --srate:48000 assets/cafe.ck:lofi:render
chuck --silent --srate:48000 assets/cafe.ck:mallets:render
chuck --silent --srate:48000 assets/cafe.ck:swing:render
chuck --silent --srate:48000 assets/cafe.ck:ambient:render
```

An optional third argument selects a different output path:

```sh
chuck --silent --srate:48000 assets/cafe.ck:bossa:render:assets/custom.wav
```

The source builds a complete circular buffer before playback or export.
Note releases and stereo room reflections wrap into the beginning, preserving
their tails without a silent splice. Peaks are normalized to approximately
−11 dBFS for headroom. Use gapless WAV playback; apply any playback start/stop
fades at the player level, rather than fading every repeat.

Edit the voicings, melody, instrument levels, and rhythms in `cafe.ck` to change
the arrangement. No external samples, plugins, Python packages, or downloads
are needed to generate the audio. The file writer uses ChucK's built-in
[WvOut2](https://chuck.stanford.edu/doc/reference/ugens-stk.html#wvout2).

## Phone ring

[phone-ring.wav](phone-ring.wav) is a gentle electronic incoming-phone
ringtone: **ring-ring, pause**, using alternating 660 / 880 Hz tones. Each
three-second cycle has two 450 ms ringing bursts separated by 250 ms,
followed by 1.85 seconds of silence. The nine-second file contains three
identical cycles and can repeat continuously. Its silence is intentional.
Both channels carry the same signal, with a peak near −12 dBFS and softened
attacks/releases. It is a custom ringtone, not a regional network ringback
tone.

```sh
# Play continuously (Ctrl-C stops).
chuck assets/phone-ring.ck

# Render silently; optionally append :assets/custom-ring.wav to the command.
chuck --silent --srate:48000 assets/phone-ring.ck:render
```
