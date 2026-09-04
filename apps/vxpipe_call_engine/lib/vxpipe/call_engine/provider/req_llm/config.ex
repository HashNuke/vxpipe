defmodule Vxpipe.CallEngine.Provider.ReqLLM.Config do
  @moduledoc false

  @derive {Inspect, only: [:model, :generation_options]}
  @enforce_keys [:api_key, :model, :generation_options]
  defstruct [:api_key, :model, :generation_options]

  @type t :: %__MODULE__{
          api_key: String.t(),
          model: term(),
          generation_options: keyword()
        }
end
