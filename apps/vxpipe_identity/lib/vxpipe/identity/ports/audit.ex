defmodule Vxpipe.Identity.Ports.Audit do
  @moduledoc "Append-only safe access-event sink."

  @callback append(event :: map()) :: :ok | {:error, term()}
end
