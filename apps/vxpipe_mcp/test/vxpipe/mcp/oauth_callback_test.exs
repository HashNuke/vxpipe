defmodule Vxpipe.MCP.OAuthCallbackTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthCallback
  @issuer "https://auth.example.test"
  @state String.duplicate("s", 43)

  test "decodes response once and validates exact issuer before returning private code" do
    query = URI.encode_query(%{"state" => @state, "code" => "private+code", "iss" => @issuer})
    assert {:ok, callback} = OAuthCallback.parse(query)
    assert callback.state == @state
    assert {:ok, "private+code"} = OAuthCallback.validate(callback, @issuer, true)
    refute inspect(callback) =~ "private"

    assert {:error, :oauth_issuer_mismatch} =
             OAuthCallback.validate(callback, @issuer <> "/", true)
  end

  test "shared callback requires iss even for legacy attempts with optional support" do
    assert {:ok, callback} =
             OAuthCallback.parse(URI.encode_query(%{"state" => @state, "code" => "code"}))

    assert {:error, :oauth_issuer_mismatch} = OAuthCallback.validate(callback, @issuer, true)
    assert {:error, :oauth_issuer_mismatch} = OAuthCallback.validate(callback, @issuer, false)

    assert {:ok, wrong} =
             OAuthCallback.parse(
               URI.encode_query(%{
                 "state" => @state,
                 "code" => "code",
                 "iss" => "https://other.test"
               })
             )

    assert {:error, :oauth_issuer_mismatch} = OAuthCallback.validate(wrong, @issuer, false)
  end

  test "ambiguous, missing and oversized callback fields fail closed" do
    for query <- [
          "code=a",
          "state=#{@state}&code=a&code=b",
          "state=#{@state}&code=a&error=denied",
          "state=#{@state}&error=",
          "state=#{@state}&code=",
          String.duplicate("x", 20_000)
        ] do
      assert {:error, :invalid_oauth_callback} = OAuthCallback.parse(query)
    end
  end

  test "provider errors are redacted and issuer checked even for denial" do
    assert {:ok, callback} =
             OAuthCallback.parse(
               URI.encode_query(%{
                 "state" => @state,
                 "error" => "access_denied",
                 "error_description" => "private",
                 "iss" => @issuer
               })
             )

    assert {:error, :oauth_consent_denied} = OAuthCallback.validate(callback, @issuer, true)

    assert {:error, :oauth_issuer_mismatch} =
             OAuthCallback.validate(callback, "https://other.test", true)

    refute inspect(callback) =~ "private"
  end
end
