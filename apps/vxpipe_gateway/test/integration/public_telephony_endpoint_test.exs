defmodule Vxpipe.Gateway.Integration.PublicTelephonyEndpointTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Gateway.HTTP.Endpoint

  @moduletag :live_providers
  @moduletag :live_telephony
  @moduletag timeout: 60_000

  setup do
    {:ok,
     port: "TELEPHONY_TEST_PORT" |> System.fetch_env!() |> String.to_integer(),
     public_url: System.fetch_env!("TELEPHONY_TEST_PUBLIC_URL")}
  end

  test "the public test URL reaches a gateway endpoint on the test port", context do
    start_supervised!(
      {Bandit, plug: {Endpoint, []}, ip: :loopback, port: context.port, startup_log: false}
    )

    # A new Funnel can take a few seconds to serve its first request.
    response =
      Req.get!(context.public_url <> "/healthz",
        retry: fn _request, response_or_error ->
          not match?(%Req.Response{status: 200}, response_or_error)
        end,
        max_retries: 10,
        retry_delay: 2_000,
        retry_log_level: false
      )

    assert response.status == 200
    assert response.body == "ok"
  end
end
