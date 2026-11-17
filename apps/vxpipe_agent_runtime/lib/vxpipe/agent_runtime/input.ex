defmodule Vxpipe.AgentRuntime.Input do
  @moduledoc """
  Structured input constructed by a trusted host before request admission.

  The host supplies participant identity and the receiving agent's mode snapshot.
  Human text is always a literal message, never decoded as an envelope. Construct
  the value once before queueing and retain it through retries. Native tool
  observations and legacy input continue to use their existing string protocol.
  """

  @derive {Inspect, only: [:origin]}
  @enforce_keys [:origin, :content]
  defstruct @enforce_keys

  @opaque t :: %__MODULE__{origin: :caller | :engine, content: String.t()}
  @type mode :: :listener | :speaker
  @maximum_bytes 64 * 1_024
  @identifier ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/

  @spec participant(String.t(), String.t(), mode()) :: {:ok, t()} | {:error, atom()}
  def participant(id, message, mode)
      when is_binary(id) and is_binary(message) and mode in [:listener, :speaker] do
    cond do
      not String.valid?(id) or not Regex.match?(@identifier, id) ->
        {:error, :invalid_input}

      byte_size(message) > @maximum_bytes ->
        {:error, :input_too_large}

      not String.valid?(message) or String.trim(message) == "" ->
        {:error, :invalid_input}

      true ->
        build(:caller, %{
          "type" => "participant_message",
          "participant_id" => id,
          "message" => message,
          "agent_mode" => Atom.to_string(mode)
        })
    end
  end

  def participant(_id, _message, _mode), do: {:error, :invalid_input}

  @spec platform(:greeting_request | :idle_timeout, map(), mode()) ::
          {:ok, t()} | {:error, atom()}
  def platform(event, data, mode)
      when event in [:greeting_request, :idle_timeout] and is_map(data) and not is_struct(data) and
             mode in [:listener, :speaker] do
    build(:engine, %{
      "type" => "platform_event",
      "event" => Atom.to_string(event),
      "data" => data,
      "agent_mode" => Atom.to_string(mode)
    })
  end

  def platform(_event, _data, _mode), do: {:error, :invalid_input}

  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{content: content}), do: content

  defp build(origin, envelope) do
    content = JSON.encode!(envelope)

    if byte_size(content) <= @maximum_bytes do
      {:ok, %__MODULE__{origin: origin, content: content}}
    else
      {:error, :input_too_large}
    end
  rescue
    _exception -> {:error, :invalid_input}
  end
end
