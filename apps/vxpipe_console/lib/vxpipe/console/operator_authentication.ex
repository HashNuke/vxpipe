defmodule Vxpipe.Console.OperatorAuthentication do
  @moduledoc "Authenticates a tenant operator for the Console call-inspection surface."

  alias Vxpipe.Calls.Principal

  @spec authenticate(String.t(), String.t(), keyword()) ::
          {:ok, Principal.t()} | {:error, term()}
  def authenticate(tenant_key, secret, options \\ [])

  def authenticate(tenant_key, secret, options)
      when is_binary(tenant_key) and is_binary(secret) and is_list(options) do
    {module, adapter_options} =
      Keyword.get_lazy(options, :authenticator, fn ->
        Application.fetch_env!(:vxpipe_console, :operator_authenticator)
      end)

    module
    |> apply(:authenticate, [adapter_options, tenant_key, secret])
    |> validate_result()
  end

  def authenticate(_tenant_key, _secret, _options), do: {:error, :invalid_api_key}

  defp validate_result({:ok, %Principal{scopes: %MapSet{} = scopes} = principal}) do
    if MapSet.member?(scopes, :calls),
      do: {:ok, principal},
      else: {:error, :insufficient_scope}
  end

  defp validate_result({:ok, _other}), do: {:error, :invalid_operator_identity}
  defp validate_result({:error, _reason} = error), do: error
  defp validate_result(_other), do: {:error, :invalid_operator_identity}
end
