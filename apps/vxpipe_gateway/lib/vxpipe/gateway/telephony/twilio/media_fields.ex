defmodule Vxpipe.Gateway.Telephony.Twilio.MediaFields do
  @moduledoc false

  @maximum_identifier_bytes 128
  @maximum_integer 2_147_483_647
  @maximum_payload_bytes 65_536

  @spec identity(keyword()) :: {:ok, map()} | :error
  def identity(options) do
    with {:ok, connection_id} <- required_option(options, :provider_connection_id),
         {:ok, call_control_id} <- required_option(options, :provider_call_control_id),
         {:ok, call_leg_id} <- required_option(options, :provider_call_leg_id),
         {:ok, call_session_id} <-
           optional_identifier(Keyword.get(options, :provider_call_session_id)) do
      {:ok,
       %{
         provider: :twilio,
         provider_connection_id: connection_id,
         provider_call_control_id: call_control_id,
         provider_call_leg_id: call_leg_id,
         provider_call_session_id: call_session_id,
         leg_id: Keyword.get(options, :leg_id)
       }}
    end
  end

  @spec string(map(), String.t()) :: {:ok, String.t()} | :error
  def string(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      value
      when is_binary(value) and byte_size(value) > 0 and
             byte_size(value) <= @maximum_identifier_bytes ->
        {:ok, value}

      _invalid ->
        :error
    end
  end

  @spec integer(map(), String.t()) :: {:ok, non_neg_integer()} | :error
  def integer(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      value when is_integer(value) and value >= 0 and value <= @maximum_integer -> {:ok, value}
      value when is_binary(value) -> parse_integer(value)
      _invalid -> :error
    end
  end

  @spec payload(term()) :: {:ok, binary()} | :error
  def payload(value) when is_binary(value) and byte_size(value) > 0 do
    with {:ok, decoded} <- Base.decode64(value),
         true <- byte_size(decoded) > 0 and byte_size(decoded) <= @maximum_payload_bytes do
      {:ok, decoded}
    else
      _invalid -> :error
    end
  end

  def payload(_invalid), do: :error

  @spec required_expected(keyword(), atom(), term()) :: :ok | :error
  def required_expected(options, key, value) do
    case Keyword.get(options, key) do
      ^value when is_binary(value) and byte_size(value) > 0 -> :ok
      _other -> :error
    end
  end

  @spec optional_expected(keyword(), atom(), term()) :: :ok | :error
  def optional_expected(options, key, value) do
    case Keyword.get(options, key) do
      nil -> :ok
      ^value -> :ok
      _other -> :error
    end
  end

  @spec observed_at(keyword()) :: {:ok, DateTime.t()} | :error
  def observed_at(options) do
    with value when is_integer(value) and value >= 0 <- Keyword.get(options, :received_at),
         {:ok, observed_at} <- DateTime.from_unix(value) do
      {:ok, observed_at}
    else
      _invalid -> :error
    end
  end

  defp required_option(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _missing -> :error
    end
  end

  defp optional_identifier(nil), do: {:ok, nil}
  defp optional_identifier(value), do: required_option([value: value], :value)

  defp parse_integer(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 and parsed <= @maximum_integer -> {:ok, parsed}
      _invalid -> :error
    end
  end
end
