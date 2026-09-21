defmodule Vxpipe.Providers.Twilio.PCMU.Format do
  @moduledoc false

  @enforce_keys [:sample_rate, :channels]
  defstruct @enforce_keys

  @type t :: %__MODULE__{sample_rate: 8_000, channels: 1}
end
