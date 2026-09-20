module Vxpipe.Gateway.WebRTC.OpusDecoder.Native

state_type "State"

spec create(sample_rate :: int) :: state

spec decode_packet(state, payload) :: payload
