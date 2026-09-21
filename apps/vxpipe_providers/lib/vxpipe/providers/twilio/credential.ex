defmodule Vxpipe.Providers.Twilio.Credential do
  @moduledoc false
  @behaviour Vxpipe.Providers.Credential

  @impl true
  def auth_kind, do: "account_sid_auth_token"

  alias Vxpipe.Providers.Twilio.Identifier

  @impl true
  def validate(
        "account_sid_auth_token",
        %{"account_sid" => sid, "auth_token" => token} = payload
      )
      when map_size(payload) == 2 and is_binary(token) and byte_size(token) in 1..4_096 do
    if Identifier.account_sid?(sid) and String.valid?(token),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(_kind, _payload), do: {:error, :invalid_provider_auth}
end
