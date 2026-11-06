defmodule Vxpipe.MCP.AuthenticationChallengeTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.AuthenticationChallenge

  test "parameter whitespace normalization preserves quoted and escaped content" do
    assert [{:basic, ~s(a = b, c " = d)}, {:bearer, [{"scope", "tools:read"}]}] =
             AuthenticationChallenge.parse(
               ~S(Basic realm = "a = b, c \" = d", Bearer scope = "tools:read")
             )
  end
end
