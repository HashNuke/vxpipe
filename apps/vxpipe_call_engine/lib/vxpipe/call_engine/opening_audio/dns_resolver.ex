defmodule Vxpipe.CallEngine.OpeningAudio.DNSResolver do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.OpeningAudio.HostResolver

  @impl true
  def resolve(host, _options) when is_binary(host) do
    hostname = String.to_charlist(host)

    addresses =
      [:inet, :inet6]
      |> Enum.flat_map(fn family ->
        case :inet.getaddrs(hostname, family) do
          {:ok, values} -> values
          {:error, _reason} -> []
        end
      end)
      |> Enum.uniq()

    if addresses == [], do: {:error, :host_not_found}, else: {:ok, addresses}
  end
end
