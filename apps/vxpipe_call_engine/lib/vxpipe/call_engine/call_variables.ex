defmodule Vxpipe.CallEngine.CallVariables do
  @moduledoc """
  Owns the private, sectioned variables for one room incarnation.
  """

  use GenServer

  alias Vxpipe.CallEngine.CallVariables.{ArchivalPort, BaselineSnapshot, State, UpdateSnapshot}
  alias Vxpipe.CallEngine.Command.{ReadCallVariables, UpdateCallVariables}
  alias Vxpipe.CallEngine.{Error, Id}

  @call_timeout 5_000
  @max_update_bytes 16_384
  @max_snapshot_bytes 65_536

  def start_link(options) do
    name = if Keyword.get(options, :register, true), do: via(options), else: nil
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      significant: true
    }
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(incarnation_id) when is_binary(incarnation_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, registry_key(incarnation_id)) do
      [{server, _value}] -> server
      [] -> nil
    end
  end

  @spec read(GenServer.server(), ReadCallVariables.t(), timeout()) ::
          {:ok, map()} | {:error, Error.t()}
  def read(server, %ReadCallVariables{} = command, timeout \\ @call_timeout) do
    GenServer.call(server, {:read, command}, timeout)
  end

  @spec update(GenServer.server(), UpdateCallVariables.t(), timeout()) ::
          {:ok, map()} | {:error, Error.t()}
  def update(server, %UpdateCallVariables{} = command, timeout \\ @call_timeout) do
    GenServer.call(server, {:update, command}, timeout)
  end

  @impl true
  def init(options) do
    plan = Keyword.fetch!(options, :plan)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    grants =
      Map.new(plan.participants, fn {_definition_key, participant} ->
        {participant.participant_id, participant.variable_permissions.grants}
      end)

    state =
      %State{
        tenant_id: plan.tenant_id,
        call_id: plan.call_id,
        room_id: plan.room_id,
        incarnation_id: incarnation_id,
        sections: plan.call_variables.sections,
        grants: grants,
        archival_port: ArchivalPort.new(Keyword.get(options, :archive_handoff)),
        source_policy: Keyword.get(options, :archive_source_policy, %{"revision" => 0}),
        global_revision: 0
      }

    {:ok, state, {:continue, :archive_baseline}}
  end

  @impl true
  def handle_continue(:archive_baseline, state) do
    :ok = ArchivalPort.handoff(state.archival_port, baseline_snapshot(state))
    {:noreply, state}
  end

  @impl true
  def handle_call({:read, command}, _from, state) do
    result =
      with :ok <- authorize_identity(command, state),
           :ok <- authorize_read(command, state),
           :ok <- ensure_current(command.deadline) do
        sections =
          Map.new(command.sections, fn name ->
            section = Map.fetch!(state.sections, name)
            {name, %{"revision" => section.revision, "value" => section.value}}
          end)

        {:ok, %{"global_revision" => state.global_revision, "sections" => sections}}
      end

    {:reply, result, state}
  end

  def handle_call({:update, command}, _from, state) do
    case apply_update(command, state) do
      {:ok, result, state} -> {:reply, {:ok, result}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  defp apply_update(command, %State{} = state) do
    with :ok <- authorize_identity(command, state),
         :ok <- authorize_write(command, state),
         :ok <- ensure_current(command.deadline),
         :ok <- ensure_operation_size(command.operation),
         {:ok, section} <- fetch_section(command.section, state),
         :ok <- ensure_revision(command.expected_revision, section),
         {:ok, candidate} <- update_candidate(command.operation, section),
         :ok <- validate_candidate(candidate, section),
         :ok <- ensure_snapshot_size(candidate) do
      revision = section.revision + 1
      global_revision = state.global_revision + 1
      section = %{section | value: candidate, revision: revision}

      state = %{
        state
        | sections: Map.put(state.sections, section.name, section),
          global_revision: global_revision
      }

      result = %{
        "section" => section.name,
        "revision" => revision,
        "global_revision" => global_revision,
        "value" => candidate
      }

      :ok = ArchivalPort.handoff(state.archival_port, update_snapshot(command, state, section))

      {:ok, result, state}
    end
  end

  defp authorize_identity(command, state) do
    if command.tenant_id == state.tenant_id and command.room_id == state.room_id and
         command.incarnation_id == state.incarnation_id and
         Map.has_key?(state.grants, command.participant_id) do
      :ok
    else
      {:error, Error.new(:call_variables_forbidden, "Call Variables access is forbidden.")}
    end
  end

  defp authorize_read(command, state) do
    grants = Map.fetch!(state.grants, command.participant_id)

    case Enum.find(command.sections, fn section ->
           Map.get(grants, section) not in [:read, :read_write] or
             not Map.has_key?(state.sections, section)
         end) do
      nil -> :ok
      section -> forbidden_section(section)
    end
  end

  defp authorize_write(command, state) do
    grants = Map.fetch!(state.grants, command.participant_id)

    if Map.get(grants, command.section) == :read_write and
         Map.has_key?(state.sections, command.section) do
      :ok
    else
      forbidden_section(command.section)
    end
  end

  defp forbidden_section(section) do
    {:error,
     Error.new(:call_variables_forbidden, "Call Variables access is forbidden.",
       details: %{"section" => section}
     )}
  end

  defp ensure_current(deadline) do
    if DateTime.compare(deadline, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, Error.new(:deadline_exceeded, "The Call Variables command deadline elapsed.")}
    end
  end

  defp ensure_operation_size(operation) do
    case encoded_size(operation_value(operation)) do
      {:ok, size} when size <= @max_update_bytes -> :ok
      _other -> invalid_update("operation exceeds the encoded-byte limit")
    end
  end

  defp operation_value({:merge, data}), do: data
  defp operation_value({:put, variable, value}), do: %{"variable" => variable, "value" => value}

  defp fetch_section(name, state) do
    case Map.fetch(state.sections, name) do
      {:ok, section} -> {:ok, section}
      :error -> forbidden_section(name)
    end
  end

  defp ensure_revision(expected, section) do
    if expected == section.revision do
      :ok
    else
      {:error,
       Error.new(:call_variables_revision_conflict, "The Call Variables revision is stale.",
         details: %{"section" => section.name, "current_revision" => section.revision}
       )}
    end
  end

  defp update_candidate({:merge, data}, section) do
    {:ok, deep_merge(section.value || %{}, data)}
  end

  defp update_candidate({:put, variable, value}, section) do
    properties = Map.get(section.schema, "properties", %{})

    if Map.has_key?(properties, variable) do
      {:ok, Map.put(section.value || %{}, variable, value)}
    else
      invalid_update("variable is not declared in the section schema")
    end
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, old, new ->
      if is_map(old) and is_map(new), do: deep_merge(old, new), else: new
    end)
  end

  defp validate_candidate(candidate, section) do
    case JSV.validate(candidate, section.validator, cast: false) do
      {:ok, ^candidate} -> :ok
      {:error, _reason} -> invalid_update("candidate does not match the section schema")
    end
  end

  defp ensure_snapshot_size(candidate) do
    case encoded_size(candidate) do
      {:ok, size} when size <= @max_snapshot_bytes -> :ok
      _other -> invalid_update("result exceeds the encoded-byte limit")
    end
  end

  defp encoded_size(value) do
    {:ok, value |> JSON.encode!() |> byte_size()}
  rescue
    Protocol.UndefinedError -> :error
    ArgumentError -> :error
  end

  defp invalid_update(reason) do
    {:error,
     Error.new(:invalid_call_variables_update, "The Call Variables update is invalid.",
       details: %{"reason" => reason}
     )}
  end

  defp update_snapshot(command, state, section) do
    %UpdateSnapshot{
      id: Id.generate(:variable_snapshot),
      command_id: command.id,
      tenant_id: state.tenant_id,
      call_id: state.call_id,
      room_id: state.room_id,
      incarnation_id: state.incarnation_id,
      participant_id: command.participant_id,
      activation_id: command.activation_id,
      source_participant_id: command.source_participant_id,
      correlation_id: command.correlation_id,
      tool_call_id: command.tool_call_id,
      section: section.name,
      section_revision: section.revision,
      global_revision: state.global_revision,
      sections: snapshot_sections(state.sections),
      source_policy: state.source_policy,
      occurred_at: DateTime.utc_now()
    }
  end

  defp baseline_snapshot(state) do
    %BaselineSnapshot{
      id: Id.generate(:variable_snapshot),
      tenant_id: state.tenant_id,
      call_id: state.call_id,
      room_id: state.room_id,
      incarnation_id: state.incarnation_id,
      global_revision: 0,
      sections: snapshot_sections(state.sections),
      source_policy: state.source_policy,
      occurred_at: DateTime.utc_now()
    }
  end

  defp snapshot_sections(sections) do
    Map.new(sections, fn {name, current} ->
      {name, %{revision: current.revision, value: current.value}}
    end)
  end

  defp via(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, registry_key(incarnation_id)}}
  end

  defp registry_key(incarnation_id), do: {:call_variables, incarnation_id}
end
