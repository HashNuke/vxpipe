defmodule Vxpipe.Gateway.TestOperatorApiKeyRepository do
  @behaviour Vxpipe.Calls.OperatorApiKeyRepository
  @impl true
  def fetch({expected, result}, digest) do
    if digest == :crypto.hash(:sha256, expected), do: result, else: {:error, :not_found}
  end

  @impl true
  def issue(_context, _record, _mode), do: {:error, :not_implemented}
  @impl true
  def revoke(_context, _id, _now), do: {:error, :not_implemented}
end
