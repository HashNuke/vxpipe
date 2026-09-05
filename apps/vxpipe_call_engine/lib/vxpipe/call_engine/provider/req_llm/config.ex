defmodule Vxpipe.CallEngine.Provider.ReqLLM.Config do
  @moduledoc false

  @derive {Inspect, only: [:model, :generation_options, :streaming]}
  @enforce_keys [:api_key, :model, :generation_options, :streaming]
  defstruct [:api_key, :model, :generation_options, :streaming]

  @type t :: %__MODULE__{
          api_key: String.t(),
          model: term(),
          generation_options: keyword(),
          streaming: boolean()
        }
end
