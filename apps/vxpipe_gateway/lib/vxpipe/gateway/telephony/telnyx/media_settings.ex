defmodule Vxpipe.Gateway.Telephony.Telnyx.MediaSettings do
  @moduledoc false

  @sample_rate 16_000

  @spec bidirectional(String.t()) :: map()
  def bidirectional(stream_url) when is_binary(stream_url) do
    %{
      "stream_url" => stream_url,
      "stream_track" => "inbound_track",
      "stream_codec" => "L16",
      "stream_bidirectional_mode" => "rtp",
      "stream_bidirectional_codec" => "L16",
      "stream_bidirectional_sampling_rate" => @sample_rate,
      "stream_bidirectional_target_legs" => "self"
    }
  end
end
