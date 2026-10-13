defmodule Vxpipe.Identity.Ports.Attempts do
  @moduledoc "Cluster-wide login/setup attempt accounting."

  @callback record(account :: String.t(), address :: String.t(), now :: DateTime.t()) :: :ok | {:error, :unavailable}
  @callback recent(account :: String.t(), address :: String.t(), now :: DateTime.t(), window_seconds :: pos_integer()) ::
              {:ok, %{account: [DateTime.t()], address: [DateTime.t()]}} | {:error, :unavailable}
end
