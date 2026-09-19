defmodule Vxpipe.Console.ProviderCredentialValidatorTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Vxpipe.Console.ProviderCredentialValidator

  setup :verify_on_exit!

  test "uses each provider's read-only authentication endpoint" do
    account_sid = "AC00000000000000000000000000000000"

    cases = [
      {"google", "api_key", %{"api_key" => "google-private"}, "/v1beta/models", "x-goog-api-key",
       "google-private"},
      {"deepgram", "api_key", %{"api_key" => "deepgram-private"}, "/v1/projects", "authorization",
       "Token deepgram-private"},
      {"zenmux", "api_key", %{"api_key" => "zenmux-private"}, "/api/v1/models", "authorization",
       "Bearer zenmux-private"},
      {"telnyx", "api_key", %{"api_key" => "telnyx-private"}, "/v2/call_control_applications",
       "authorization", "Bearer telnyx-private"},
      {"twilio", "account_sid_auth_token",
       %{"account_sid" => account_sid, "auth_token" => "twilio-private"},
       "/2010-04-01/Accounts/#{account_sid}.json", "authorization",
       "Basic " <> Base.encode64("#{account_sid}:twilio-private")}
    ]

    for {provider, auth_kind, payload, path, header, value} <- cases do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == path
        assert get_req_header(conn, header) == [value]
        Req.Test.json(conn, %{ok: true})
      end)

      assert :ok = ProviderCredentialValidator.validate(options(), provider, auth_kind, payload)
    end
  end

  test "checks Rime authentication using dictionary coverage without synthesizing audio" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.host == "users.rime.ai"
      assert conn.request_path == "/oov"
      assert get_req_header(conn, "authorization") == ["Bearer rime-example"]
      {:ok, body, conn} = read_body(conn)
      assert JSON.decode!(body) == %{"text" => "hello"}
      Req.Test.json(conn, [])
    end)

    assert :ok =
             ProviderCredentialValidator.validate(options(), "rime", "api_key", %{
               "api_key" => "rime-example"
             })
  end

  test "distinguishes rejected credentials from temporary provider failure" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn |> put_status(401) |> Req.Test.json(%{error: "do not expose this body"})
    end)

    assert {:error, :provider_credential_rejected} =
             ProviderCredentialValidator.validate(
               options(),
               "google",
               "api_key",
               %{"api_key" => "rejected"}
             )

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> put_status(503) |> Req.Test.json(%{error: "temporary"})
    end)

    assert {:error, :provider_validation_unavailable} =
             ProviderCredentialValidator.validate(
               options(),
               "deepgram",
               "api_key",
               %{"api_key" => "unavailable"}
             )
  end

  defp options do
    [request_options: [plug: {Req.Test, __MODULE__}]]
  end

  defp verify_on_exit!(_context) do
    Req.Test.verify_on_exit!()
    :ok
  end
end
