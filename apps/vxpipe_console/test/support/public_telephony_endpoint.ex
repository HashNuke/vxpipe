defmodule Vxpipe.Console.Test.PublicTelephonyEndpoint do
  @moduledoc false

  import ExUnit.Assertions

  def resolve(origin) do
    uri = URI.parse(origin)
    assert uri.scheme == "https" and is_binary(uri.host)

    assert {:ok, response} =
             Req.get("https://dns.google/resolve",
               params: [name: uri.host, type: "A"],
               retry: false,
               receive_timeout: 5_000
             )

    assert response.status == 200

    endpoints =
      response.body
      |> Map.get("Answer", [])
      |> Enum.filter(&(Map.get(&1, "type") == 1))
      |> Enum.map(fn answer ->
        address = Map.fetch!(answer, "data")
        assert {:ok, {_, _, _, _}} = :inet.parse_address(String.to_charlist(address))
        %{origin: URI.to_string(%{uri | host: address}), hostname: uri.host}
      end)

    assert endpoints != [], "public DNS returned no IPv4 Funnel relay; no dial submitted"
    endpoints
  end

  def ready?(endpoints, probe \\ &request/4) do
    results = Enum.map(endpoints, &probe.(&1, :get, "/healthz", receive_timeout: 3_000))

    results != [] and
      Enum.all?(results, &match?({:ok, %Req.Response{status: 200, body: "ok"}}, &1))
  end

  def request(endpoint, method, path, options \\ []) do
    options
    |> Keyword.put(:url, endpoint.origin <> path)
    |> Keyword.put(:method, method)
    |> Keyword.put(:connect_options, hostname: endpoint.hostname, timeout: 3_000)
    |> Keyword.put(:retry, false)
    |> Req.request()
  end
end
