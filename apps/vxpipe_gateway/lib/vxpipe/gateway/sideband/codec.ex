defmodule Vxpipe.Gateway.Sideband.Codec do
  @moduledoc false

  @maximum_payload_bytes 4_096
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/

  @type acceptance :: %{id: String.t(), attempt_id: String.t()}

  @spec handle(binary()) :: :ignore | {:reply, binary()} | {:command, {:accept, acceptance()}}
  def handle(payload) when is_binary(payload) and byte_size(payload) <= @maximum_payload_bytes do
    with {:ok, message} when is_map(message) <- JSON.decode(payload) do
      handle_message(message)
    else
      _invalid -> :ignore
    end
  end

  def handle(_payload), do: :ignore

  @spec encode_preparation(String.t(), String.t()) :: {:ok, binary()}
  def encode_preparation(attempt_id, participant_id) do
    encode(attempt_id, "transfer.preparation", %{
      "attempt_id" => attempt_id,
      "participant_id" => participant_id
    })
  end

  @spec encode_active(String.t()) :: {:ok, binary()}
  def encode_active(attempt_id) do
    encode(attempt_id, "transfer.active", %{"attempt_id" => attempt_id})
  end

  @spec encode_error(String.t()) :: binary()
  def encode_error(id) do
    JSON.encode!(%{
      "id" => id,
      "type" => "error",
      "data" => %{"message" => "The transfer control could not be accepted."}
    })
  end

  defp handle_message(%{
         "id" => id,
         "type" => "transfer.accept",
         "data" => %{"attempt_id" => attempt_id}
       }) do
    if identifier?(id) and identifier?(attempt_id) do
      {:command, {:accept, %{id: id, attempt_id: attempt_id}}}
    else
      invalid_acceptance(id)
    end
  end

  defp handle_message(_message), do: :ignore

  defp invalid_acceptance(id) do
    if identifier?(id), do: {:reply, encode_error(id)}, else: :ignore
  end

  defp encode(id, type, data) do
    {:ok, JSON.encode!(%{"id" => id, "type" => type, "data" => data})}
  end

  defp identifier?(value) when is_binary(value), do: Regex.match?(@identifier_pattern, value)
  defp identifier?(_value), do: false
end
