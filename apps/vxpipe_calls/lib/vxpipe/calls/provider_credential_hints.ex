defmodule Vxpipe.Calls.ProviderCredentialHints do
  @moduledoc "Derives bounded, non-secret credential hints for operator inventory views."

  @spec from_payload(String.t(), map()) :: %{optional(String.t()) => String.t()}
  def from_payload("api_key", %{"api_key" => api_key}),
    do: %{"api_key" => last_four(api_key)}

  def from_payload("account_sid_auth_token", %{"account_sid" => account_sid}),
    do: %{"account_sid" => last_four(account_sid)}

  def from_payload(_auth_kind, _payload), do: %{}

  defp last_four(value) when is_binary(value), do: String.slice(value, -4, 4)
end
