defmodule Vxpipe.Console.MCPOAuthReturnLocationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.MCPOAuthReturnLocation
  @tenant "AAAAAAAAAAAAAAAA"
  @base "/t/AAAAAAAAAAAAAAAA/services"

  test "canonicalizes a bounded tenant category, search and cursor" do
    assert {:ok, @base} = MCPOAuthReturnLocation.validate(@tenant, nil)

    assert {:ok, @base <> "/calendar"} =
             MCPOAuthReturnLocation.validate(@tenant, @base <> "/calendar")

    assert {:ok, path} =
             MCPOAuthReturnLocation.validate(
               @tenant,
               @base <> "/search?q=calendar+tools&cursor=opaque%2B%2F%3D"
             )

    assert URI.parse(path).path == @base <> "/search"

    assert URI.decode_query(URI.parse(path).query) == %{
             "q" => "calendar tools",
             "cursor" => "opaque+/="
           }

    completed = MCPOAuthReturnLocation.connected(@tenant, path)
    assert URI.parse(completed).path == @base <> "/search"

    assert URI.decode_query(URI.parse(completed).query) == %{
             "q" => "calendar tools",
             "cursor" => "opaque+/=",
             "mcp" => "connected"
           }
  end

  test "rejects redirects and parameters outside this tenant's integration view" do
    for path <- [
          "https://other.test",
          "//other.test",
          "/t/BBBBBBBBBBBBBBBB/services",
          "/platform/services",
          "/account",
          @base <> "/../account",
          @base <> "/%2e%2e",
          @base <> "\\evil",
          @base <> "#fragment",
          @base <> "?q=one&q=two",
          @base <> "?code=private",
          @base <> "?redirect_uri=https://other.test",
          @base <> "?q=" <> String.duplicate("a", 201),
          @base <> "?cursor=" <> String.duplicate("a", 2049),
          @base <> "?q=%0A",
          @base <> "/search/extra",
          42,
          ""
        ] do
      assert {:error, :invalid_oauth_return_location} =
               MCPOAuthReturnLocation.validate(@tenant, path)
    end

    assert MCPOAuthReturnLocation.connected(@tenant, "https://other.test") ==
             @base <> "?mcp=connected"

    assert MCPOAuthReturnLocation.connected(@tenant, nil) == @base <> "?mcp=connected"
  end
end
