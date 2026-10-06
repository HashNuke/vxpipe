defmodule Vxpipe.CallEngine.CallSpec.Direction do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.ConnectionIntent
  alias Vxpipe.CallEngine.CallSpecValidation, as: Validation

  @code :invalid_call_spec
  @message "The call spec is invalid."
  @legacy_version "20260915.01"

  @enforce_keys [:kind, :caller, :handled_by, :caller_path, :handler_path]
  defstruct @enforce_keys ++ [ring_timeout_ms: nil, legacy?: false]

  def new(input, @legacy_version) do
    with :ok <- reject_fields(input, [:incoming_call, :outgoing_call]),
         {:ok, caller} <- identifier(input, :entry_caller, []),
         {:ok, handled_by} <- identifier(input, :entry_receiver, []) do
      {:ok,
       %__MODULE__{
         kind: :incoming,
         caller: caller,
         handled_by: handled_by,
         caller_path: ["entry_caller"],
         handler_path: ["entry_receiver"],
         legacy?: true
       }}
    end
  end

  def new(input, _version) do
    with :ok <- reject_fields(input, [:entry_caller, :entry_receiver]) do
      case {Map.fetch(input, :incoming_call), Map.fetch(input, :outgoing_call)} do
        {{:ok, value}, :error} -> parse(value, :incoming)
        {:error, {:ok, value}} -> parse(value, :outgoing)
        _other -> invalid([], "must declare exactly one of incoming_call or outgoing_call")
      end
    end
  end

  def participant_options(direction, key) do
    [
      outgoing_callee?: direction.kind == :outgoing and key == direction.caller,
      first_message_default:
        if(direction.kind == :outgoing and key == direction.handled_by,
          do: "generated",
          else: "wait_for_input"
        )
    ]
  end

  def validate(direction, participants) do
    with {:ok, caller} <- participant(participants, direction.caller, direction.caller_path),
         {:ok, _handler} <-
           participant(participants, direction.handled_by, direction.handler_path),
         :ok <- different_participants(direction),
         :ok <- human(caller, direction.caller_path) do
      validate_connection(direction, caller.connection)
    end
  end

  defp parse(value, kind) do
    {block, caller_field, fields} =
      case kind do
        :incoming -> {"incoming_call", :caller, [:caller, :handled_by]}
        :outgoing -> {"outgoing_call", :callee, [:callee, :handled_by, :ring_timeout_ms]}
      end

    with {:ok, input} <- Validation.normalize_map(value, fields, @code, @message, [block]),
         {:ok, caller} <- identifier(input, caller_field, [block]),
         {:ok, handled_by} <- identifier(input, :handled_by, [block]),
         {:ok, timeout} <- ring_timeout(input, kind) do
      {:ok,
       %__MODULE__{
         kind: kind,
         caller: caller,
         handled_by: handled_by,
         caller_path: [block, Atom.to_string(caller_field)],
         handler_path: [block, "handled_by"],
         ring_timeout_ms: timeout
       }}
    end
  end

  defp reject_fields(input, fields) do
    case Enum.find(fields, &Map.has_key?(input, &1)) do
      nil -> :ok
      field -> invalid([Atom.to_string(field)], "is not supported in this schema version")
    end
  end

  defp identifier(input, field, path) do
    with {:ok, value} <- Validation.fetch(input, field, @code, @message, path) do
      Validation.identifier(value, @code, @message, path ++ [Atom.to_string(field)])
    end
  end

  defp ring_timeout(_input, :incoming), do: {:ok, nil}

  defp ring_timeout(input, :outgoing) do
    case Map.get(input, :ring_timeout_ms, 30_000) do
      timeout when is_integer(timeout) and timeout >= 5_000 and timeout <= 60_000 ->
        {:ok, timeout}

      _invalid ->
        invalid(["outgoing_call", "ring_timeout_ms"], "must be between 5000 and 60000")
    end
  end

  defp participant(participants, key, path) do
    case Map.fetch(participants, key) do
      {:ok, participant} -> {:ok, participant}
      :error -> invalid(path, "must reference a participant")
    end
  end

  defp different_participants(%{caller: same, handled_by: same} = direction),
    do: invalid(direction.handler_path, "must differ from the caller or callee")

  defp different_participants(_direction), do: :ok

  defp human(%{kind: :human}, _path), do: :ok
  defp human(_participant, path), do: invalid(path, "must reference a human participant")

  # Preserve validation/execution of historical specs, including their original entry contract.
  defp validate_connection(%{legacy?: true}, _connection), do: :ok

  defp validate_connection(
         %{kind: :incoming},
         %ConnectionIntent{mode: :receive, admission: :start_call}
       ),
       do: :ok

  defp validate_connection(
         %{kind: :outgoing},
         %ConnectionIntent{service: service, mode: :dial, admission: :start_call}
       )
       when is_binary(service),
       do: :ok

  defp validate_connection(direction, _connection),
    do: invalid(direction.caller_path, "must have the direction's initial connection intent")

  defp invalid(path, reason), do: Validation.invalid(@code, @message, path, reason)
end
