defmodule Vxpipe.Artifacts.Document do
  @moduledoc "Exact immutable document bytes addressed by a protected object key."

  @derive {Inspect, except: [:contents, :checksum]}
  @enforce_keys [:object_key, :contents, :checksum, :content_type]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          object_key: String.t(),
          contents: binary(),
          checksum: binary(),
          content_type: String.t()
        }

  @spec new(String.t(), binary(), binary()) :: {:ok, t()} | {:error, :invalid_document}
  def new(object_key, contents, checksum)
      when is_binary(object_key) and is_binary(contents) and is_binary(checksum) do
    if valid_key?(object_key) and contents != "" and byte_size(checksum) == 32 and
         :crypto.hash(:sha256, contents) == checksum do
      {:ok,
       %__MODULE__{
         object_key: object_key,
         contents: contents,
         checksum: checksum,
         content_type: "application/json"
       }}
    else
      {:error, :invalid_document}
    end
  end

  def new(_object_key, _contents, _checksum), do: {:error, :invalid_document}

  defp valid_key?(value) do
    value != "" and byte_size(value) <= 1_024 and
      not String.contains?(value, ["..", "://", "?", "#"]) and
      not String.starts_with?(value, "/")
  end
end
