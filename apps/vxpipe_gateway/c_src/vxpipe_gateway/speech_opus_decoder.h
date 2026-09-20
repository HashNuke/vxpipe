#pragma once

#include <opus/opus.h>
#include <unifex/unifex.h>

typedef struct State State;

struct State {
  opus_int32 sample_rate;
  OpusDecoder *decoder;
};

#include "_generated/speech_opus_decoder.h"
