defmodule Vxpipe.Providers.Twilio.CredentialValidation do
  @moduledoc false

  @behaviour Vxpipe.Providers.CredentialValidation

  @impl true
  def request(
        "account_sid_auth_token",
        %{"account_sid" => account_sid, "auth_token" => auth_token} = payload
      )
      when map_size(payload) == 2 do
    {:ok,
     [
       url: "https://api.twilio.com/2010-04-01/Accounts/" <> account_sid <> ".json",
       headers: [
         {"accept", "application/json"},
         {"authorization", "Basic " <> Base.encode64(account_sid <> ":" <> auth_token)}
       ]
     ]}
  end

  def request(_auth_kind, _payload), do: {:error, :provider_validation_unsupported}
end
