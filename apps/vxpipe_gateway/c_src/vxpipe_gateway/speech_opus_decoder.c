#include "speech_opus_decoder.h"

UNIFEX_TERM create(UnifexEnv *env, int sample_rate) {
  State *state = unifex_alloc_state(env);
  int error = OPUS_OK;

  state->decoder = opus_decoder_create(sample_rate, 1, &error);
  state->sample_rate = sample_rate;

  if (error != OPUS_OK) {
    unifex_release_state(env, state);
    return unifex_raise(env, (char *)opus_strerror(error));
  }

  UNIFEX_TERM result = create_result(env, state);
  unifex_release_state(env, state);
  return result;
}

UNIFEX_TERM decode_packet(UnifexEnv *env, State *state,
                          UnifexPayload *input) {
  int samples =
      opus_packet_get_nb_samples(input->data, input->size, state->sample_rate);

  if (samples < 0) {
    return unifex_raise(env, (char *)opus_strerror(samples));
  }

  UnifexPayload output;
  unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY,
                       samples * sizeof(opus_int16), &output);

  int decoded = opus_decode(state->decoder, input->data, input->size,
                            (opus_int16 *)output.data, samples, 0);

  if (decoded < 0) {
    unifex_payload_release(&output);
    return unifex_raise(env, (char *)opus_strerror(decoded));
  }

  if (decoded != samples) {
    unifex_payload_release(&output);
    return unifex_raise(env, "invalid decoded output size");
  }

  return decode_packet_result(env, &output);
}

void handle_destroy_state(UnifexEnv *env, State *state) {
  UNIFEX_UNUSED(env);

  if (state->decoder) {
    opus_decoder_destroy(state->decoder);
  }
}
