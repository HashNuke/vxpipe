defmodule Vxpipe.Calls.IssuedOperatorApiKey do
  @moduledoc "An installation API key returned only at trusted issuance."
  @enforce_keys [:id, :secret, :inserted_at]
  @derive {Inspect, only: [:id, :inserted_at]}
  defstruct @enforce_keys

  @type t :: %__MODULE__{id: String.t(), secret: String.t(), inserted_at: DateTime.t()}
end
