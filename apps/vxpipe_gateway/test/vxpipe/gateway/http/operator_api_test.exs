defmodule Vxpipe.Gateway.HTTP.OperatorApiTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias Vxpipe.Gateway.HTTP.{Endpoint, Mount}

  @key "vxop_" <> String.duplicate("a", 43)
  @id "11111111-1111-4111-8111-111111111111"

  test "operator status requires a current installation key and returns metadata only" do
    for result <- [{:ok, %{id: @id, revoked_at: DateTime.utc_now()}}, {:error, :not_found}] do
      assert request(@key, options(result)).status == 401
    end

    assert request(nil, options()).status == 401
    assert request("vxp_" <> String.duplicate("a", 43), options()).status == 401
    assert request(@key, options({:error, :repository_unavailable})).status == 503

    response = request(@key, options())
    assert response.status == 200

    assert JSON.decode!(response.resp_body) == %{
             "authority" => "installation_operator",
             "api_key_id" => @id
           }

    refute response.resp_body =~ @key
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert request(@key, Endpoint.init([])).status == 404
  end

  test "host mount routes the explicit platform status path" do
    config = Mount.init(operator_api: settings())

    response =
      conn(:get, "/api/platform/status")
      |> put_req_header("authorization", "Bearer " <> @key)
      |> Mount.call(config)

    assert response.status == 200
    assert response.halted
  end

  defp request(key, config) do
    connection = conn(:get, "/api/platform/status")

    connection =
      if key, do: put_req_header(connection, "authorization", "Bearer " <> key), else: connection

    Endpoint.call(connection, config)
  end

  defp options(result \\ {:ok, %{id: @id, revoked_at: nil}}),
    do: Endpoint.init(operator_api: settings(result))

  defp settings(result \\ {:ok, %{id: @id, revoked_at: nil}}),
    do: [
      enabled: true,
      operator_api_key_repository: {Vxpipe.Gateway.TestOperatorApiKeyRepository, {@key, result}}
    ]
end
