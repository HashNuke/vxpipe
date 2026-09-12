defmodule Vxpipe.Calls.CallDetailsObject do
  @moduledoc "A protected object-store receipt for published call-details bytes."

  @derive {Inspect, except: [:reference]}
  @enforce_keys [:object_key, :reference, :published_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          object_key: String.t(),
          reference: map(),
          published_at: DateTime.t()
        }

  @spec new(String.t(), map(), DateTime.t()) ::
          {:ok, t()} | {:error, :invalid_call_details_object}
  def new(object_key, reference, %DateTime{} = published_at)
      when is_binary(object_key) and is_map(reference) do
    with true <- valid_object_key?(object_key),
         true <- utc?(published_at),
         {:ok, reference} <- canonical_json(reference),
         true <- valid_reference?(reference, object_key) do
      {:ok,
       %__MODULE__{
         object_key: object_key,
         reference: reference,
         published_at: published_at
       }}
    else
      _invalid -> {:error, :invalid_call_details_object}
    end
  end

  def new(_object_key, _reference, _published_at),
    do: {:error, :invalid_call_details_object}

  defp valid_object_key?(value),
    do:
      value != "" and byte_size(value) <= 1_024 and
        not String.contains?(value, ["..", "://", "?", "#"]) and
        not String.starts_with?(value, "/")

  defp valid_reference?(%{"object_key" => object_key} = reference, object_key) do
    Map.keys(reference) |> Enum.all?(&(&1 in ["object_key", "etag"])) and
      optional_string?(Map.get(reference, "etag"), 1_024)
  end

  defp valid_reference?(_reference, _object_key), do: false

  defp optional_string?(nil, _maximum), do: true

  defp optional_string?(value, maximum),
    do: is_binary(value) and value != "" and byte_size(value) <= maximum

  defp canonical_json(value) do
    {:ok, value |> JSON.encode!() |> JSON.decode!()}
  rescue
    _error -> {:error, :not_json_safe}
  end

  defp utc?(value), do: value.utc_offset == 0 and value.std_offset == 0
end
