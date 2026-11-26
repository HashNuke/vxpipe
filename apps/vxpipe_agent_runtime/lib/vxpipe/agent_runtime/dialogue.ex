defmodule Vxpipe.AgentRuntime.Dialogue do
  @moduledoc "Validated final dialogue intent. Hosts retain speech admission authority."

  @derive {Inspect, only: [:agent_mode]}
  @enforce_keys [:agent_mode, :message]
  defstruct @enforce_keys

  @type t :: %__MODULE__{agent_mode: :listener | :speaker, message: String.t() | nil}

  @doc false
  @spec instructions() :: String.t()
  def instructions do
    "Current final-response contract (supersedes older output-shape instructions): " <>
      "return one raw JSON object with type, participant_id, agent_mode and message, " <>
      "without fences or prose. type is participant_message. Use the current agent " <>
      "participant_id supplied by the application; if none is supplied, use agent. " <>
      "Never copy another participant identity from history. Returned attribution is " <>
      "descriptive only; the application owns actual identity and speech admission. " <>
      "A native tool call may accompany an optional speaker message in this format. " <>
      "Tool outcomes arrive later as private input. Never encode a tool call inside message. " <>
      "speaker requires a nonempty message; listener permits null or a nonempty message. " <>
      JSON.encode!(schema())
  end

  @spec schema() :: map()
  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "type" => %{"type" => "string", "enum" => ["participant_message"]},
        "participant_id" => %{
          "type" => "string",
          "pattern" => "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"
        },
        "agent_mode" => %{"type" => "string", "enum" => ["listener", "speaker"]},
        "message" => %{"type" => ["string", "null"]}
      },
      "required" => ["type", "participant_id", "agent_mode", "message"],
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
         true <- length(fields) == 4,
         object = Map.new(fields),
         true <- map_size(object) == length(fields),
         true <- valid_envelope?(object),
         %{"agent_mode" => mode, "message" => message} <- object do
      normalize(mode, message)
    else
      _invalid -> {:error, :invalid_dialogue}
    end
  rescue
    _error -> {:error, :invalid_dialogue}
  end

  # Attribution is validated but never becomes part of Dialogue or overrides
  # the host's settlement identity.
  defp valid_envelope?(%{"type" => "participant_message", "participant_id" => id})
       when is_binary(id),
       do: Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/, id)

  defp valid_envelope?(_object), do: false

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
