defmodule Vxpipe.MCP.OAuthRequestParametersTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthRequestParameters

  test "accepts bounded literal provider values and preserves their spelling" do
    assert {:ok, %{}} = OAuthRequestParameters.validate([])

    assert {:ok, %{"prompt" => "consent", "organization" => "Team café"}} =
             OAuthRequestParameters.validate([
               %{"name" => "prompt", "value" => "consent"},
               %{"name" => "organization", "value" => "Team café"}
             ])
  end

  test "rejects every managed field, duplicates, malformed values and oversized requests" do
    for name <-
          ~w(response_type client_id client_secret redirect_uri scope state code_challenge code_challenge_method resource audience grant_type code refresh_token access_token token_type client_assertion client_assertion_type authorization) do
      for key <- [name, String.upcase(name)] do
        assert {:error, :invalid_oauth_parameters} =
                 OAuthRequestParameters.validate([%{"name" => key, "value" => "override"}])
      end
    end

    for pairs <- [
          %{"prompt" => "consent"},
          [%{"name" => "prompt", "value" => "x"}, %{"name" => "prompt", "value" => "y"}],
          [%{"name" => "", "value" => "x"}],
          [%{"name" => "bad key", "value" => "x"}],
          [%{"name" => "prompt", "value" => "x\ny"}],
          [%{"name" => "prompt", "value" => 1}],
          [%{"name" => "prompt", "value" => "x", "extra" => true}],
          [%{"name" => "prompt", "value" => String.duplicate("x", 8193)}],
          Enum.map(1..33, &%{"name" => "field#{&1}", "value" => "x"}),
          Enum.map(1..3, &%{"name" => "field#{&1}", "value" => String.duplicate("x", 8192)})
        ] do
      assert {:error, :invalid_oauth_parameters} = OAuthRequestParameters.validate(pairs)
    end
  end

  test "rejects request-object and response-mode indirection and bounds explicit audience" do
    for name <- ~w(request request_uri response_mode assertion) do
      assert {:error, :invalid_oauth_parameters} =
               OAuthRequestParameters.validate([
                 %{"name" => name, "value" => "indirect-override"}
               ])
    end

    assert {:ok, %{"audience" => "provider-api"}} =
             OAuthRequestParameters.validate([], "provider-api")

    for audience <- ["", "bad\naudience", 1, String.duplicate("x", 2049)] do
      assert {:error, :invalid_oauth_parameters} = OAuthRequestParameters.validate([], audience)
    end
  end
end
