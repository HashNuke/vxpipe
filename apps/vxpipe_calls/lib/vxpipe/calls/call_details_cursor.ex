defmodule Vxpipe.Calls.CallDetailsCursor do
  @moduledoc false

  @enforce_keys [:recorded_at, :publication_id]
  defstruct @enforce_keys

  @type t :: %__MODULE__{recorded_at: DateTime.t(), publication_id: String.t()}

  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{} = cursor) do
    %{
      "recorded_at" => DateTime.to_iso8601(cursor.recorded_at),
      "publication_id" => cursor.publication_id
    }
    |> JSON.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(String.t()) :: {:ok, t()} | {:error, :invalid_cursor}
  def decode(encoded) when is_binary(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, %{"recorded_at" => timestamp, "publication_id" => publication_id}} <-
           JSON.decode(json),
         {:ok, recorded_at, 0} <- DateTime.from_iso8601(timestamp),
         true <-
           is_binary(publication_id) and byte_size(publication_id) > 0 and
             byte_size(publication_id) <= 256 do
      {:ok, %__MODULE__{recorded_at: recorded_at, publication_id: publication_id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  rescue
    _invalid -> {:error, :invalid_cursor}
  end

  def decode(_invalid), do: {:error, :invalid_cursor}
end
