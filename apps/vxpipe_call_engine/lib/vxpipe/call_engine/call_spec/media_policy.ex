defmodule Vxpipe.CallEngine.CallDefinition.MediaPolicy do
  @moduledoc false

  alias Vxpipe.CallEngine.DefinitionValidation

  @code :invalid_call_definition
  @message "The call definition is invalid."
  @fields [:audio_routes, :transcript_routes, :record_audio, :save_transcripts]

  @enforce_keys @fields
  defstruct @fields

  @type routes :: :inherit | %{String.t() => [String.t()]}
  @type permission :: :inherit | boolean()

  @type t :: %__MODULE__{
          audio_routes: routes(),
          transcript_routes: routes(),
          record_audio: permission(),
          save_transcripts: permission()
        }

  @spec from_optional(:error | {:ok, term()}, [String.t()]) ::
          {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def from_optional(:error, _path), do: {:ok, inherit()}
  def from_optional({:ok, value}, path), do: new(value, path)

  @spec validate_references(t(), map(), [String.t()]) ::
          :ok | {:error, Vxpipe.CallEngine.Error.t()}
  def validate_references(%__MODULE__{} = policy, participants, path)
      when is_map(participants) do
    with :ok <-
           validate_route_references(policy.audio_routes, participants, path ++ ["audio_routes"]),
         :ok <-
           validate_route_references(
             policy.transcript_routes,
             participants,
             path ++ ["transcript_routes"]
           ) do
      :ok
    end
  end

  defp new(value, path) do
    with {:ok, input} <-
           DefinitionValidation.normalize_map(value, @fields, @code, @message, path),
         {:ok, audio_routes} <- routes(Map.fetch(input, :audio_routes), path ++ ["audio_routes"]),
         {:ok, transcript_routes} <-
           routes(Map.fetch(input, :transcript_routes), path ++ ["transcript_routes"]),
         {:ok, record_audio} <-
           permission(Map.fetch(input, :record_audio), path ++ ["record_audio"]),
         {:ok, save_transcripts} <-
           permission(Map.fetch(input, :save_transcripts), path ++ ["save_transcripts"]) do
      {:ok,
       %__MODULE__{
         audio_routes: audio_routes,
         transcript_routes: transcript_routes,
         record_audio: record_audio,
         save_transcripts: save_transcripts
       }}
    end
  end

  defp inherit do
    %__MODULE__{
      audio_routes: :inherit,
      transcript_routes: :inherit,
      record_audio: :inherit,
      save_transcripts: :inherit
    }
  end

  defp routes(:error, _path), do: {:ok, :inherit}

  defp routes({:ok, value}, path) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn
      {source, recipients}, {:ok, routes} when is_binary(source) ->
        source_path = path ++ [source]

        with {:ok, source} <- identifier(source, source_path),
             {:ok, recipients} <- recipients(recipients, source_path) do
          {:cont, {:ok, Map.put(routes, source, recipients)}}
        else
          {:error, _error} = error -> {:halt, error}
        end

      {_source, _recipients}, _acc ->
        {:halt, invalid(path ++ ["<invalid-key>"], "source names must be strings")}
    end)
  end

  defp routes({:ok, _value}, path), do: invalid(path, "must be an object")

  defp recipients(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {recipient, index}, {:ok, acc, seen} ->
      recipient_path = path ++ [Integer.to_string(index)]

      case identifier(recipient, recipient_path) do
        {:ok, recipient} ->
          if MapSet.member?(seen, recipient) do
            {:halt, invalid(recipient_path, "must not be duplicated")}
          else
            {:cont, {:ok, [recipient | acc], MapSet.put(seen, recipient)}}
          end

        {:error, _error} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, recipients, _seen} -> {:ok, Enum.reverse(recipients)}
      {:error, _error} = error -> error
    end
  end

  defp recipients(_value, path), do: invalid(path, "must be an array of participant references")

  defp permission(:error, _path), do: {:ok, :inherit}
  defp permission({:ok, value}, _path) when is_boolean(value), do: {:ok, value}
  defp permission({:ok, _value}, path), do: invalid(path, "must be a boolean")

  defp validate_route_references(:inherit, _participants, _path), do: :ok

  defp validate_route_references(routes, participants, path) do
    Enum.reduce_while(routes, :ok, fn {source, recipients}, :ok ->
      result =
        if Map.has_key?(participants, source) do
          validate_recipient_references(recipients, participants, path ++ [source])
        else
          invalid(path ++ [source], "must reference a participant")
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp validate_recipient_references(recipients, participants, path) do
    recipients
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {recipient, index}, :ok ->
      if Map.has_key?(participants, recipient) do
        {:cont, :ok}
      else
        {:halt, invalid(path ++ [Integer.to_string(index)], "must reference a participant")}
      end
    end)
  end

  defp identifier(value, path) do
    DefinitionValidation.identifier(value, @code, @message, path)
  end

  defp invalid(path, reason) do
    DefinitionValidation.invalid(@code, @message, path, reason)
  end
end
