defmodule Vxpipe.Calls.PreparedMCPOAuth do
  @moduledoc "Private protocol preparation passed to authorized attempt persistence."
  @derive {Inspect, only: []}
  @enforce_keys [:authorization_url, :attributes, :secrets]
  defstruct @enforce_keys
  @type t :: %__MODULE__{authorization_url: String.t(), attributes: map(), secrets: map()}
end
