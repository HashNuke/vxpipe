defmodule Vxpipe.CallEngine.Provider.SpeechToText do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  @callback new(keyword()) :: {:ok, struct()} | {:error, atom()}
  @callback connection_options(config :: struct()) :: map()
  @callback media_format(config :: struct()) :: %{
              required(:codec) => atom(),
              required(:sample_rate) => pos_integer()
            }
  @callback decode(binary()) ::
              {:ok, Signal.t()}
              | {:ignore, atom()}
              | {:error, atom()}
end
