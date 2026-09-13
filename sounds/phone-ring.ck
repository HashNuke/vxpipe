// A rounded electronic telephone double-ring: ring-ring, pause, repeat.
// Play:   chuck assets/phone-ring.ck                  (Ctrl-C stops)
// Render: chuck --silent --srate:48000 assets/phone-ring.ck:render
// Optional second argument: output WAV path. Stock ChucK only.

me.args() > 0 && me.arg(0) == "render" => int rendering;
me.dir() + "phone-ring.wav" => string destination;
if(me.args() > 1) me.arg(1) => destination;

second / samp => float sampleRate;
(9.0 * sampleRate) $ int => int frames;
float sound[frames];
2.0 * pi => float tau;

// Three identical three-second cycles. Each has two 450 ms ringing bursts
// separated by 250 ms, followed by 1.85 seconds of intentional silence.
for(0 => int cycle; cycle < 3; cycle++)
{
    for(0 => int burst; burst < 2; burst++)
    {
        ((cycle * 3.0 + burst * 0.7) * sampleRate) $ int => int start;
        (0.45 * sampleRate) $ int => int length;
        for(0 => int i; i < length; i++)
        {
            i / sampleRate => float t;
            1.0 => float envelope;
            if(t < 0.012) 0.5 - 0.5 * Math.cos(pi * t / 0.012) => envelope;
            if(t > 0.425) (0.5 - 0.5 * Math.cos(pi * (0.45 - t) / 0.025)) *=> envelope;
            // Alternating pitches make a familiar phone trill; the envelope
            // rounds the attack and release instead of abruptly gating it.
            0.5 + 0.5 * Math.sin(tau * 20.0 * t) => float alternate;
            alternate * Math.sin(tau * 660.0 * t)
                + (1.0 - alternate) * Math.sin(tau * 880.0 * t) => float tone;
            0.25 * envelope * tone => sound[start + i];
        }
    }
}

Step output;
WvOut2 writer;
if(rendering)
{
    output => writer.chan(0);
    output => writer.chan(1);
    writer => blackhole;
    writer.wavFilename(destination, IO.INT16);
    1.0 => writer.fileGain;
}
else
{
    output => dac.chan(0);
    output => dac.chan(1);
    <<< "Playing phone ring: ring-ring, pause. Ctrl-C to stop." >>>;
}

do
{
    for(0 => int i; i < frames; i++)
    {
        sound[i] => output.next;
        1::samp => now;
    }
} while(!rendering);

if(rendering)
{
    writer.closeFile();
    <<< "Rendered " + destination >>>;
}
