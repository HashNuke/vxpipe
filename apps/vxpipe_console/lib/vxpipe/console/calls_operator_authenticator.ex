defmodule Vxpipe.Console.CallsOperatorAuthenticator do
  @moduledoc false

  @behaviour Vxpipe.Console.OperatorAuthenticator

  alias Vxpipe.Calls

  @impl true
  def authenticate(options, tenant_key, secret) do
    Calls.authenticate(tenant_key, secret, :calls, options)
  end
end
