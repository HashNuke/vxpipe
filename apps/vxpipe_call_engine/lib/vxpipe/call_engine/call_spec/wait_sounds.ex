defmodule Vxpipe.CallEngine.CallSpec.WaitSounds do
  @moduledoc "Call-level wait sources, resolved from omitted defaults, URLs, or explicit silence."

  alias Vxpipe.CallEngine.CallSpecValidation

  @defaults [
    call_setup: :phone_ring,
    transfer_to_agent: :cafe_bossa,
    transfer_to_human: :phone_ring,
    transfer_joining: :cafe_bossa
  ]
  @slots Keyword.keys(@defaults)
  @derive {Inspect, only: []}
  defstruct @defaults

  @type source :: :phone_ring | :cafe_bossa | String.t() | nil
  @type t :: %__MODULE__{
          call_setup: source(),
          transfer_to_agent: source(),
          transfer_to_human: source(),
          transfer_joining: source()
        }

  @code :invalid_call_spec
  @message "The call spec is invalid."

  @spec from_optional(:error | {:ok, term()}) ::
          {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def from_optional(:error), do: {:ok, %__MODULE__{}}
  def from_optional({:ok, nil}), do: {:ok, struct!(__MODULE__, Map.new(@slots, &{&1, nil}))}

  def from_optional({:ok, value}) do
    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, @slots, @code, @message, ["wait_sounds"]),
         {:ok, selections} <- selections(input) do
      {:ok, struct!(__MODULE__, selections)}
    end
  end

  defp selections(input) do
    Enum.reduce_while(input, {:ok, %{}}, fn {slot, value}, {:ok, selected} ->
      case source(value, ["wait_sounds", Atom.to_string(slot)]) do
        {:ok, source} -> {:cont, {:ok, Map.put(selected, slot, source)}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp source(nil, _path), do: {:ok, nil}

  defp source(value, path) do
    with {:ok, url} <- CallSpecValidation.string(value, @code, @message, path, maximum: 2_048),
         {:ok, uri} <- URI.new(url),
         true <- uri.scheme in ["http", "https"],
         true <- is_binary(uri.host) and uri.host != "",
         true <- is_nil(uri.userinfo) and is_nil(uri.fragment),
         true <- is_integer(uri.port) and uri.port in 1..65_535 do
      {:ok, url}
    else
      _invalid ->
        CallSpecValidation.invalid(
          @code,
          @message,
          path,
          "must be an absolute HTTP(S) audio-file URL without user information or fragment, or null"
        )
    end
  end
end
