defmodule Vxpipe.CallEngine.CallVariables.Binding do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables
  alias Vxpipe.CallEngine.Command.{ReadCallVariables, UpdateCallVariables}
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Tool.{Context, ReadVariables, UpdateVariable, UpdateVariables}

  @command_timeout_ms 4_000
  @variable_tool_names ["read_variables", "update_variables", "update_variable"]

  @derive {Inspect,
           except: [
             :server,
             :read_sections,
             :write_sections
           ]}
  @enforce_keys [
    :server,
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :activation_id,
    :read_sections,
    :write_sections
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          server: GenServer.server(),
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t(),
          read_sections: [String.t()],
          write_sections: [String.t()]
        }

  @spec new(pid(), Vxpipe.CallEngine.ResolvedCallPlan.t(), map(), String.t()) :: t()
  def new(server, plan, participant, incarnation_id)
      when is_pid(server) and is_binary(incarnation_id) do
    grants = participant.variable_permissions.grants

    %__MODULE__{
      server: server,
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: incarnation_id,
      participant_id: participant.participant_id,
      activation_id: participant.activation_id,
      read_sections: readable_sections(grants),
      write_sections: writable_sections(grants)
    }
  end

  @spec actions(map() | t()) :: [module()]
  def actions(%__MODULE__{} = binding) do
    actions(binding.read_sections != [], binding.write_sections != [])
  end

  def actions(grants) when is_map(grants) do
    actions(
      map_size(grants) > 0,
      Enum.any?(grants, fn {_section, grant} -> grant == :read_write end)
    )
  end

  @spec variable_tool?(String.t()) :: boolean()
  def variable_tool?(name) when is_binary(name), do: name in @variable_tool_names

  @spec permitted_tool?(t(), String.t()) :: boolean()
  def permitted_tool?(%__MODULE__{} = binding, "read_variables"),
    do: binding.read_sections != []

  def permitted_tool?(%__MODULE__{} = binding, name)
      when name in ["update_variables", "update_variable"],
      do: binding.write_sections != []

  def permitted_tool?(%__MODULE__{}, _name), do: false

  @spec execute(t(), String.t(), map(), Context.t()) ::
          {:ok, map()} | {:error, :invalid_arguments | :tool_failed}
  def execute(%__MODULE__{} = binding, name, arguments, %Context{} = context) do
    with :ok <- authorize_context(binding, context),
         {:ok, command} <- command(binding, name, arguments, context) do
      command
      |> dispatch(binding)
      |> normalize_result()
    else
      {:error, %Error{} = error} -> normalize_result({:error, error})
      {:error, reason} when reason in [:invalid_arguments, :tool_failed] -> {:error, reason}
      _invalid -> {:error, :tool_failed}
    end
  end

  @spec projection(t()) :: {:ok, map()} | {:error, :tool_failed}
  def projection(%__MODULE__{} = binding) do
    options = identity_options(binding)

    with {:ok, command} <-
           ReadCallVariables.new(
             options ++
               [sections: binding.read_sections, deadline: deadline()]
           ),
         {:ok, projection} <- CallVariables.read(binding.server, command, @command_timeout_ms) do
      {:ok, projection}
    else
      _error -> {:error, :tool_failed}
    end
  end

  defp readable_sections(grants) do
    grants
    |> Enum.filter(fn {_section, grant} -> grant in [:read, :read_write] end)
    |> Enum.map(fn {section, _grant} -> section end)
    |> Enum.sort()
  end

  defp writable_sections(grants) do
    grants
    |> Enum.filter(fn {_section, grant} -> grant == :read_write end)
    |> Enum.map(fn {section, _grant} -> section end)
    |> Enum.sort()
  end

  defp actions(read?, write?) do
    read = if read?, do: [ReadVariables], else: []
    write = if write?, do: [UpdateVariables, UpdateVariable], else: []
    read ++ write
  end

  defp authorize_context(binding, context) do
    if context.tenant_id == binding.tenant_id and context.room_id == binding.room_id and
         context.incarnation_id == binding.incarnation_id and
         context.agent_participant_id == binding.participant_id do
      :ok
    else
      {:error, :tool_failed}
    end
  end

  defp command(binding, "read_variables", arguments, _context) do
    with {:ok, sections} <- fetch(arguments, :sections) do
      ReadCallVariables.new(
        identity_options(binding) ++
          [sections: sections, deadline: deadline()]
      )
    end
  end

  defp command(binding, "update_variables", arguments, context) do
    with {:ok, section} <- fetch(arguments, :section_name),
         {:ok, data} <- fetch(arguments, :data),
         {:ok, revision} <- fetch(arguments, :expected_revision) do
      update_command(binding, context,
        section: section,
        expected_revision: revision,
        operation: {:merge, data}
      )
    end
  end

  defp command(binding, "update_variable", arguments, context) do
    with {:ok, section} <- fetch(arguments, :section_name),
         {:ok, variable} <- fetch(arguments, :variable_name),
         {:ok, value} <- fetch(arguments, :value),
         {:ok, revision} <- fetch(arguments, :expected_revision) do
      update_command(binding, context,
        section: section,
        expected_revision: revision,
        operation: {:put, variable, value}
      )
    end
  end

  defp command(_binding, _name, _arguments, _context), do: {:error, :tool_failed}

  defp update_command(binding, context, options) do
    UpdateCallVariables.new(
      identity_options(binding) ++
        [
          activation_id: binding.activation_id,
          source_participant_id: context.source_participant_id,
          correlation_id: context.correlation_id,
          tool_call_id: context.tool_call_id || context.agent_request_id || context.command_id,
          deadline: deadline()
        ] ++ options
    )
  end

  defp identity_options(binding) do
    [
      tenant_id: binding.tenant_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: binding.participant_id
    ]
  end

  defp fetch(arguments, key) do
    case Map.fetch(arguments, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(arguments, Atom.to_string(key))
    end
  end

  defp dispatch(%ReadCallVariables{} = command, binding) do
    CallVariables.read(binding.server, command, @command_timeout_ms)
  end

  defp dispatch(%UpdateCallVariables{} = command, binding) do
    CallVariables.update(binding.server, command, @command_timeout_ms)
  end

  defp normalize_result({:ok, result}), do: {:ok, result}

  defp normalize_result({:error, %Error{} = error}) do
    {:ok, %{"error" => Error.to_public(error)}}
  end

  defp deadline, do: DateTime.add(DateTime.utc_now(), @command_timeout_ms, :millisecond)
end
