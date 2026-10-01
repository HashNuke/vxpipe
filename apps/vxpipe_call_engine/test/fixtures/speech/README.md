# Speech activity reference

`silero_v6.2.3.f32` contains 130 little-endian float32 probabilities from the
official wrapper for the pinned model, processing the committed public
`vxpipe_providers/test/fixtures/deepgram/final_word_16k_mono_s16le.pcm` fixture.
The source model revision and checksum are recorded in
[the packaged model notice](../../../priv/speech/README.md).

These expected values verify the project-owned PCM normalization, input context,
ordered tensors and recurrent-state assembly. Irregular PCM chunking must retain
the same probabilities; a reset must reproduce the initial stream result.
The file contains no credentials or user audio.
