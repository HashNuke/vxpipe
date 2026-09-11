defmodule Vxpipe.Gateway.Telephony.Twilio.Identifier do
  @moduledoc false

  @account_sid ~r/\AAC[0-9a-fA-F]{32}\z/
  @call_sid ~r/\ACA[0-9a-fA-F]{32}\z/

  @spec account_sid?(term()) :: boolean()
  def account_sid?(value), do: matches?(value, @account_sid)

  @spec call_sid?(term()) :: boolean()
  def call_sid?(value), do: matches?(value, @call_sid)

  defp matches?(value, pattern) when is_binary(value), do: Regex.match?(pattern, value)
  defp matches?(_invalid, _pattern), do: false
end
