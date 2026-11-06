defmodule Vxpipe.Calls.Test.MCPOAuthPreparationFixture do
  def prepare({owner, result}, _tenant, input, origin) do
    send(owner, {:oauth_prepare, input, origin})
    result
  end
end
