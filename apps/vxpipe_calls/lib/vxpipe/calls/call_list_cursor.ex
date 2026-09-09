defmodule Vxpipe.Calls.CallListCursor do
  @moduledoc false

  @enforce_keys [:created_at, :call_id]
  defstruct @enforce_keys

  @type t :: %__MODULE__{created_at: DateTime.t(), call_id: String.t()}

  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{} = cursor) do
    %{"created_at" => DateTime.to_iso8601(cursor.created_at), "call_id" => cursor.call_id}
    |> JSON.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(String.t()) :: {:ok, t()} | {:error, :invalid_cursor}
  def decode(encoded) when is_binary(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, %{"created_at" => timestamp, "call_id" => call_id}} <- JSON.decode(json),
         {:ok, created_at, 0} <- DateTime.from_iso8601(timestamp),
         true <- is_binary(call_id) and byte_size(call_id) > 0 and byte_size(call_id) <= 256 do
      {:ok, %__MODULE__{created_at: created_at, call_id: call_id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_invalid), do: {:error, :invalid_cursor}
end
