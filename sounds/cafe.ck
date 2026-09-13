// Original nine-second cafe loops, synthesized entirely in ChucK.
// Play:   chuck assets/cafe.ck:keys        (Ctrl-C stops)
// Styles: keys, bossa, lofi, mallets, swing, ambient.
// Render: chuck --silent --srate:48000 assets/cafe.ck:keys:render
// Optional third argument: output WAV path. No samples or chugins needed.

"keys" => string style;
if(me.args() > 0) me.arg(0) => style;
if(style != "keys" && style != "bossa" && style != "lofi"
    && style != "mallets" && style != "swing" && style != "ambient")
{
    <<< "Choose keys, bossa, lofi, mallets, swing, or ambient." >>>;
    me.exit();
}
me.args() > 1 && me.arg(1) == "render" => int rendering;
me.dir() + "cafe-" + style + ".wav" => string destination;
if(me.args() > 2) me.arg(2) => destination;

second / samp => float sampleRate;
9.0 => float seconds;
(seconds * sampleRate) $ int => int frames;
seconds / 16.0 => float beat;
2.0 * pi => float tau;
float left[frames];
float right[frames];
float roomLeft[frames];
float roomRight[frames];
Math.srandom(7319);

// Write onto a circle: late notes and their tails continue at the beginning.
fun void place(int frame, float value, float pan, float room)
{
    frame % frames => int index;
    value * Math.sqrt((1.0 - pan) * 0.5) => float l;
    value * Math.sqrt((1.0 + pan) * 0.5) => float r;
    l +=> left[index];
    r +=> right[index];
    l * room +=> roomLeft[index];
    r * room +=> roomRight[index];
}

// Cosine-ended envelopes reach zero with zero slope, even across the seam.
fun float fade(float t, float length, float attack, float release)
{
    1.0 => float envelope;
    if(t < attack) 0.5 - 0.5 * Math.cos(pi * t / attack) => envelope;
    if(t > length - release)
        (0.5 - 0.5 * Math.cos(pi * (length - t) / release)) *=> envelope;
    return envelope;
}

// instrument: 0 = mellow tine piano, 1 = nylon-like pluck, 2 = round bass.
//             3 = soft vibraphone-like mallet, 4 = slow warm pad.
fun void note(float at, int midi, float length, float volume, float pan, int instrument)
{
    Std.mtof(midi) => float frequency;
    (at * beat * sampleRate) $ int => int start;
    (length * sampleRate) $ int => int count;
    0.018 => float attack;
    0.14 => float release;
    0.32 => float room;
    if(instrument == 1) 0.006 => attack;
    if(instrument == 2) { 0.012 => attack; 0.04 => room; }
    if(instrument == 3) { 0.009 => attack; 0.44 => room; }
    if(instrument == 4) { 0.65 => attack; 1.4 => release; 0.5 => room; }

    for(0 => int i; i < count; i++)
    {
        i / sampleRate => float t;
        tau * frequency * t => float phase;
        0.0 => float tone;
        if(instrument == 0)
        {
            Math.sin(phase + 0.42 * Math.exp(-t / 0.22) * Math.sin(phase))
                + 0.16 * Math.exp(-t / 0.4) * Math.sin(2.0 * phase)
                + 0.035 * Math.exp(-t / 0.18) * Math.sin(3.0 * phase) => tone;
            Math.exp(-t / 1.15) *=> tone;
        }
        else if(instrument == 1)
        {
            Math.sin(phase) + 0.38 * Math.exp(-t / 0.32) * Math.sin(2.0 * phase)
                + 0.17 * Math.exp(-t / 0.2) * Math.sin(3.0 * phase)
                + 0.07 * Math.exp(-t / 0.1) * Math.sin(4.0 * phase) => tone;
            Math.exp(-t / 0.65) *=> tone;
        }
        else if(instrument == 2)
        {
            (Math.sin(phase) + 0.28 * Math.sin(2.0 * phase)
                + 0.08 * Math.sin(3.0 * phase)) * Math.exp(-t / 0.55) => tone;
        }
        else if(instrument == 3)
        {
            (Math.sin(phase) + 0.14 * Math.exp(-t / 0.24) * Math.sin(4.0 * phase)
                + 0.022 * Math.exp(-t / 0.09) * Math.sin(9.2 * phase))
                * Math.exp(-t / 0.85) * (0.92 + 0.08 * Math.cos(tau * 4.8 * t)) => tone;
        }
        else
        {
            (Math.sin(phase) + 0.12 * Math.sin(2.0 * phase)
                + 0.035 * Math.sin(3.0 * phase))
                * (0.94 + 0.06 * Math.cos(tau * 0.4 * t)) => tone;
        }
        place(start + i, volume * tone * fade(t, length, attack, release), pan, room);
    }
}

fun void chord(float at, int notes[], float volume, int instrument)
{
    for(0 => int n; n < notes.size(); n++)
    {
        // Tiny strum offsets make the voicing feel played.
        note(at + n * 0.012, notes[n], 2.4, volume,
            -0.32 + n * 0.14, instrument);
    }
}

// Quiet synthesized percussion: shaker, brush, low kick, and woody rim.
fun void drum(float at, int kind, float volume, float pan)
{
    (at * beat * sampleRate) $ int => int start;
    0.22 => float length;
    if(kind == 1) 0.32 => length;
    (length * sampleRate) $ int => int count;
    0.0 => float low;
    for(0 => int i; i < count; i++)
    {
        i / sampleRate => float t;
        Math.random2f(-1.0, 1.0) => float noise;
        low + 0.24 * (noise - low) => low;
        0.0 => float tone;
        if(kind == 0) (noise - low) * Math.exp(-t / 0.025) => tone;
        if(kind == 1) low * Math.exp(-t / 0.07) => tone;
        if(kind == 2)
            Math.sin(tau * (54.0 * t + 1.6 * (1.0 - Math.exp(-t / 0.022))))
                * Math.exp(-t / 0.065) => tone;
        if(kind == 3)
            (0.65 * Math.sin(tau * 810.0 * t) + 0.35 * Math.sin(tau * 1230.0 * t))
                * Math.exp(-t / 0.012) => tone;
        place(start + i, tone * volume * fade(t, length, 0.003, 0.04), pan, 0.12);
    }
}

// Four bars at 106 2/3 BPM: Cmaj9 / Am9 / Dm9 / G13.
// The final dominant returns naturally to the opening C chord.
[[60, 64, 67, 71, 74], [60, 64, 67, 71, 76],
 [60, 65, 69, 72, 76], [59, 64, 65, 69, 74]] @=> int voicings[][];
[36, 33, 38, 31] @=> int roots[];

// Give the new acoustic arrangements their own register and key.
0 => int transpose;
if(style == "mallets") 5 => transpose; // F major.
if(style == "swing") 3 => transpose;  // E-flat major.
for(0 => int bar; bar < 4; bar++)
{
    transpose +=> roots[bar];
    for(0 => int n; n < voicings[bar].size(); n++)
        transpose +=> voicings[bar][n];
}

if(style == "keys")
{
    // Spacious electric piano, gently moving bass, and barely-there brushes.
    for(0 => int bar; bar < 4; bar++)
    {
        bar * 4.0 => float at;
        chord(at, voicings[bar], 0.105, 0);
        chord(at + 2.65, voicings[bar], 0.035, 0);
        note(at, roots[bar] + 12, 1.65, 0.115, 0.0, 2);
        note(at + 2.5, roots[bar] + 19, 0.9, 0.065, 0.0, 2);
        drum(at + 1.0, 1, 0.023, 0.18);
        drum(at + 3.0, 1, 0.018, -0.18);
    }
    [2.0, 3.25, 6.0, 7.5, 10.0, 11.25, 14.0, 15.25] @=> float times[];
    [76, 74, 71, 67, 69, 72, 74, 71] @=> int melody[];
    for(0 => int i; i < melody.size(); i++)
        note(times[i], melody[i], 1.75, 0.072, 0.22, 0);
}
else if(style == "bossa")
{
    // Muted nylon-like comping, root/fifth bass, and a light bossa pulse.
    for(0 => int bar; bar < 4; bar++)
    {
        bar * 4.0 => float at;
        chord(at, voicings[bar], 0.083, 1);
        chord(at + 1.5, voicings[bar], 0.055, 1);
        chord(at + 3.0, voicings[bar], 0.064, 1);
        note(at, roots[bar] + 12, 0.95, 0.15, -0.06, 2);
        note(at + 2.0, roots[bar] + 19, 0.9, 0.12, -0.06, 2);
        drum(at + 1.0, 3, 0.035, -0.2);
        drum(at + 2.5, 3, 0.026, -0.2);
        for(0 => int eighth; eighth < 8; eighth++)
            drum(at + eighth * 0.5, 0, 0.027 + (eighth % 2) * 0.012, 0.3);
    }
    [0.5, 1.5, 3.5, 4.5, 6.5, 8.5, 10.0, 11.5, 12.5, 14.5] @=> float times[];
    [76, 79, 76, 74, 71, 69, 72, 76, 74, 71] @=> int melody[];
    for(0 => int i; i < melody.size(); i++)
        note(times[i], melody[i], 1.4, 0.077, 0.24, 0);
}
else if(style == "lofi")
{
    // Half-time jazz pocket: Rhodes-like chords, rounded kick, brushed snare.
    for(0 => int bar; bar < 4; bar++)
    {
        bar * 4.0 => float at;
        chord(at + 0.035, voicings[bar], 0.1, 0);
        chord(at + 3.35, voicings[bar], 0.039, 0);
        note(at, roots[bar], 1.45, 0.17, 0.0, 2);
        note(at + 3.0, roots[bar] + 12, 0.55, 0.08, 0.0, 2);
        drum(at, 2, 0.1, 0.0);
        drum(at + 2.06, 1, 0.11, 0.07);
        drum(at + 2.06, 3, 0.021, 0.07);
        if(bar % 2 == 1) drum(at + 3.5, 2, 0.065, 0.0);
        for(0 => int eighth; eighth < 8; eighth++)
            drum(at + eighth * 0.5 + (eighth % 2) * 0.08,
                0, 0.021 + (eighth % 2) * 0.009, -0.3);
    }
    [1.65, 3.1, 7.25, 9.65, 11.1, 15.1] @=> float times[];
    [79, 76, 71, 72, 69, 74] @=> int melody[];
    for(0 => int i; i < melody.size(); i++)
        note(times[i], melody[i], 2.0, 0.057, 0.25, 0);
}
else if(style == "mallets")
{
    // Sunny vibraphone-like melody over quiet plucked comping in F major.
    for(0 => int bar; bar < 4; bar++)
    {
        bar * 4.0 => float at;
        chord(at, voicings[bar], 0.06, 1);
        chord(at + 2.5, voicings[bar], 0.033, 1);
        note(at, roots[bar] + 12, 1.1, 0.12, -0.05, 2);
        note(at + 2.0, roots[bar] + 19, 0.8, 0.085, -0.05, 2);
        drum(at + 1.0, 1, 0.033, 0.12);
        drum(at + 3.0, 1, 0.028, 0.12);
        for(0 => int pulse; pulse < 4; pulse++)
            drum(at + pulse + 0.62, 0, 0.02, -0.26);
    }
    [0.5, 1.5, 2.75, 4.5, 5.5, 7.0, 8.5, 9.5, 10.75, 12.5, 14.0, 15.0]
        @=> float times[];
    [77, 81, 79, 77, 76, 72, 74, 77, 81, 79, 76, 72] @=> int melody[];
    for(0 => int i; i < melody.size(); i++)
        note(times[i], melody[i], 1.8, 0.095, 0.16, 3);
}
else if(style == "swing")
{
    // A small brushed jazz trio in E-flat: walking bass and swung eighths.
    [4, 3, 3, 4] @=> int thirds[];
    for(0 => int bar; bar < 4; bar++)
    {
        bar * 4.0 => float at;
        chord(at + 0.025, voicings[bar], 0.075, 0);
        chord(at + 1.67, voicings[bar], 0.042, 0);
        chord(at + 3.0, voicings[bar], 0.035, 0);
        [roots[bar] + 12, roots[bar] + 12 + thirds[bar], roots[bar] + 19,
            roots[(bar + 1) % 4] + 11] @=> int walk[];
        for(0 => int quarter; quarter < 4; quarter++)
        {
            note(at + quarter, walk[quarter], 0.48, 0.125, -0.08, 2);
            drum(at + quarter, 0, 0.022, 0.3);
            drum(at + quarter + 0.67, 0, 0.013, 0.3);
        }
        drum(at + 1.025, 1, 0.062, -0.15);
        drum(at + 3.025, 1, 0.052, -0.15);
    }
    [0.67, 1.0, 2.67, 3.0, 4.67, 6.0, 7.67, 8.67, 9.0, 10.67, 12.67, 14.0, 15.0]
        @=> float times[];
    [79, 77, 74, 70, 75, 74, 70, 72, 75, 79, 77, 74, 70] @=> int melody[];
    for(0 => int i; i < melody.size(); i++)
        note(times[i], melody[i], 1.15, 0.071, 0.22, 0);
}
else if(style == "ambient")
{
    // Two slow, overlapping Amaj9 / Dmaj9 colors, without a drum pulse.
    [[57, 61, 64, 68, 71], [54, 57, 61, 64, 69]] @=> int pads[][];
    [45, 38] @=> int anchors[];
    for(0 => int half; half < 2; half++)
    {
        half * 8.0 => float at;
        for(0 => int n; n < pads[half].size(); n++)
            note(at, pads[half][n], 6.8, 0.042, -0.42 + n * 0.21, 4);
        note(at, anchors[half], 2.0, 0.068, 0.0, 2);
        note(at + 4.0, anchors[half] + 12, 1.7, 0.035, 0.0, 2);
    }
    [0.5, 2.0, 4.5, 6.5, 8.5, 10.0, 12.5, 14.5] @=> float times[];
    [73, 76, 71, 68, 69, 73, 76, 71] @=> int melody[];
    for(0 => int i; i < melody.size(); i++)
        note(times[i], melody[i], 2.7, 0.06, 0.2, 0);
}

// A short stereo room made from circular taps: no reverb gets cut off.
[0.071, 0.113, 0.173, 0.241, 0.337, 0.449, 0.593] @=> float delays[];
[0.30, 0.25, 0.20, 0.16, 0.12, 0.09, 0.06] @=> float returns[];
for(0 => int tap; tap < delays.size(); tap++)
{
    (delays[tap] * sampleRate) $ int => int offset;
    for(0 => int i; i < frames; i++)
    {
        (i + offset) % frames => int target;
        if(tap % 2 == 0)
        {
            roomRight[i] * returns[tap] +=> left[target];
            roomLeft[i] * returns[tap] +=> right[target];
        }
        else
        {
            roomLeft[i] * returns[tap] +=> left[target];
            roomRight[i] * returns[tap] +=> right[target];
        }
    }
}

// Remove DC and leave ample headroom; do not fade the repeating file's edges.
0.0 => float meanLeft;
0.0 => float meanRight;
for(0 => int i; i < frames; i++) { left[i] +=> meanLeft; right[i] +=> meanRight; }
frames /=> meanLeft;
frames /=> meanRight;
0.0 => float peak;
for(0 => int i; i < frames; i++)
{
    meanLeft -=> left[i];
    meanRight -=> right[i];
    Math.max(peak, Math.max(Math.fabs(left[i]), Math.fabs(right[i]))) => peak;
}
0.28 / Math.max(peak, 0.001) => float level;

Step outputLeft;
Step outputRight;
WvOut2 writer;
if(rendering)
{
    outputLeft => writer.chan(0);
    outputRight => writer.chan(1);
    writer => blackhole;
    writer.wavFilename(destination, IO.INT16);
    1.0 => writer.fileGain;
}
else
{
    outputLeft => dac.chan(0);
    outputRight => dac.chan(1);
    <<< "Playing cafe-" + style + ": nine-second loop. Ctrl-C to stop." >>>;
}

do
{
    for(0 => int i; i < frames; i++)
    {
        left[i] * level => outputLeft.next;
        right[i] * level => outputRight.next;
        1::samp => now;
    }
} while(!rendering);

if(rendering)
{
    writer.closeFile();
    <<< "Rendered " + destination >>>;
}
