defmodule Vxpipe.Console.TestOperatorAuthenticator do
  @moduledoc false

  @behaviour Vxpipe.Console.OperatorAuthenticator

  alias Vxpipe.Calls.Principal

  @impl true
  def authenticate(observer, tenant_key, secret) do
    send(observer, {:operator_authentication, tenant_key, secret})

    case secret do
      "valid-api-key" ->
        {:ok,
         %Principal{
           tenant_key: tenant_key,
           api_key_id: "01234567-89ab-4cde-8fab-0123456789ab",
           scopes: MapSet.new([:calls])
         }}

      "wrong-scope" ->
        {:ok,
         %Principal{
           tenant_key: tenant_key,
           api_key_id: "01234567-89ab-4cde-8fab-0123456789ab",
           scopes: MapSet.new([:admin])
         }}

      _other ->
        {:error, :invalid_api_key}
    end
  end
end
