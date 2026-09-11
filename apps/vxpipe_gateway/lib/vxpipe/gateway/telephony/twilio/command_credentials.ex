defmodule Vxpipe.Gateway.Telephony.Twilio.CommandCredentials do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.Twilio.Identifier

  @type t :: %{account_sid: String.t(), auth_token: String.t()}

  @spec fetch(keyword()) ::
          {:ok, t()}
          | {:error,
             :invalid_twilio_account_sid
             | {:missing_twilio_option, :account_sid | :auth_token}}
  def fetch(options) do
    with {:ok, account_sid} <- required_option(options, :account_sid),
         true <- Identifier.account_sid?(account_sid),
         {:ok, auth_token} <- required_option(options, :auth_token) do
      {:ok, %{account_sid: account_sid, auth_token: auth_token}}
    else
      false -> {:error, :invalid_twilio_account_sid}
      {:error, _reason} = error -> error
    end
  end

  defp required_option(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_twilio_option, key}}
    end
  end
end
