defmodule Vxpipe.CallEngine.Telephony.CallerIdentity do
  @moduledoc "Normalizes reported caller numbers and SIP addresses without inferring identities."

  @phone_number ~r/\A\+[1-9][0-9]{1,14}\z/
  @sip_uri ~r/\A(?:(?<scheme>sips?):)?(?<user>[^\s<>:@?]+)@(?<host>\[[0-9a-f:]+\]|[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?)(?<suffix>(?::[0-9]{1,5})?(?:[;?][^\s<>]*)?)\z/i

  @spec phone_number(term()) :: String.t() | nil
  def phone_number(value) when is_binary(value) do
    if Regex.match?(@phone_number, value), do: value
  end

  def phone_number(_value), do: nil

  @spec sip_uri(term()) :: String.t() | nil
  def sip_uri(value) when is_binary(value) and byte_size(value) <= 512 do
    case Regex.named_captures(@sip_uri, value) do
      %{"scheme" => scheme, "user" => user, "host" => host, "suffix" => suffix} ->
        scheme = if scheme == "", do: "sip", else: String.downcase(scheme)
        scheme <> ":" <> user <> "@" <> String.downcase(host) <> suffix

      nil ->
        nil
    end
  end

  def sip_uri(_value), do: nil

  @spec display_name(term()) :: String.t() | nil
  def display_name(value) when is_binary(value) and byte_size(value) in 1..128 do
    if String.valid?(value) and not String.contains?(value, ["\r", "\n", <<0>>]), do: value
  end

  def display_name(_value), do: nil
end
