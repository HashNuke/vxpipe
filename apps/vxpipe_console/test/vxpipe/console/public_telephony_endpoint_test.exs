defmodule Vxpipe.Console.PublicTelephonyEndpointTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.Test.PublicTelephonyEndpoint

  test "dial readiness requires every DNS relay, including the last one" do
    endpoints = [:first, :second, :third]
    observer = self()

    probe = fn endpoint, :get, "/healthz", _options ->
      send(observer, {:probed, endpoint})

      case endpoint do
        :third -> {:error, %Req.TransportError{reason: :timeout}}
        _healthy -> {:ok, %Req.Response{status: 200, body: "ok"}}
      end
    end

    refute PublicTelephonyEndpoint.ready?(endpoints, probe)
    for endpoint <- endpoints, do: assert_received({:probed, ^endpoint})
  end

  test "a healthy subset or an empty DNS result never permits a dial" do
    for response <- [
          {:ok, %Req.Response{status: 503, body: "ok"}},
          {:ok, %Req.Response{status: 200, body: "not ready"}}
        ] do
      refute PublicTelephonyEndpoint.ready?([:relay], fn _, _, _, _ -> response end)
    end

    refute PublicTelephonyEndpoint.ready?([], fn _, _, _, _ -> flunk("no relay") end)
  end

  test "all relays serving the actual gateway health response permit dialing" do
    assert PublicTelephonyEndpoint.ready?([:one, :two, :three], fn _, _, _, _ ->
             {:ok, %Req.Response{status: 200, body: "ok"}}
           end)
  end
end
