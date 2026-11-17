defmodule Vxpipe.AgentRuntime.Dialogue do
  @moduledoc "Validated final dialogue intent. Hosts retain speech admission authority."

  @derive {Inspect, only: [:agent_mode]}
  @enforce_keys [:agent_mode, :message]
  defstruct @enforce_keys

  @type t :: %__MODULE__{agent_mode: :listener | :speaker, message: String.t() | nil}

  @spec schema() :: map()
  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "agent_mode" => %{"type" => "string", "enum" => ["listener", "speaker"]},
        "message" => %{"type" => ["string", "null"]}
      },
      "required" => ["agent_mode", "message"],
      "additionalProperties" => false
    }
  end

  @spec decode(String.t(), pos_integer()) :: {:ok, t()} | {:error, atom()}
  def decode(text, maximum_bytes \\ 256 * 1_024)

  def decode(text, maximum_bytes)
      when is_binary(text) and is_integer(maximum_bytes) and maximum_bytes > 0 do
    cond do
      byte_size(text) > maximum_bytes -> {:error, :output_too_large}
      not String.valid?(text) -> {:error, :invalid_dialogue}
      true -> decode_object(text)
    end
  end

  def decode(_text, _maximum_bytes), do: {:error, :invalid_dialogue}

  defp decode_object(text) do
    # Retain field pairs until uniqueness has been checked. A map decoder silently
    # accepts duplicate JSON keys and would hide ambiguous control instructions.
    decoder = [object_finish: fn fields, state -> {{:object, fields}, state} end]

    with {{:object, fields}, nil, rest} <- JSON.decode(text, nil, decoder),
         true <- json_end?(rest),
         true <- length(fields) == 2,
         object = Map.new(fields),
         true <- map_size(object) == 2,
         %{"agent_mode" => mode, "message" => message} <- object do
      normalize(mode, message)
    else
      _invalid -> {:error, :invalid_dialogue}
    end
  rescue
    _error -> {:error, :invalid_dialogue}
  end

  defp json_end?(""), do: true
  defp json_end?(<<byte, rest::binary>>) when byte in [9, 10, 13, 32], do: json_end?(rest)
  defp json_end?(_suffix), do: false

  defp normalize("listener", nil), do: {:ok, %__MODULE__{agent_mode: :listener, message: nil}}

  defp normalize(mode, message) when mode in ["listener", "speaker"] and is_binary(message) do
    if String.trim(message) != "" do
      mode = if mode == "speaker", do: :speaker, else: :listener
      {:ok, %__MODULE__{agent_mode: mode, message: message}}
    else
      {:error, :invalid_dialogue}
    end
  end

  defp normalize(_mode, _message), do: {:error, :invalid_dialogue}
end
