defmodule Vxpipe.Persistence.ResolvedPlanCodec do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan

  @legacy_struct_modules %{
    Vxpipe.CallEngine.CallDefinition => Vxpipe.CallEngine.CallSpec,
    Vxpipe.CallEngine.CallDefinition.CallVariables => Vxpipe.CallEngine.CallSpec.CallVariables,
    Vxpipe.CallEngine.CallDefinition.Capabilities => Vxpipe.CallEngine.CallSpec.Capabilities,
    Vxpipe.CallEngine.CallDefinition.CapabilityRequirements =>
      Vxpipe.CallEngine.CallSpec.CapabilityRequirements,
    Vxpipe.CallEngine.CallDefinition.CapabilitySelection =>
      Vxpipe.CallEngine.CallSpec.CapabilitySelection,
    Vxpipe.CallEngine.CallDefinition.ConnectionIntent =>
      Vxpipe.CallEngine.CallSpec.ConnectionIntent,
    Vxpipe.CallEngine.CallDefinition.MediaPolicy => Vxpipe.CallEngine.CallSpec.MediaPolicy,
    Vxpipe.CallEngine.CallDefinition.NumberFromVariable =>
      Vxpipe.CallEngine.CallSpec.NumberFromVariable,
    Vxpipe.CallEngine.CallDefinition.OpeningAudio => Vxpipe.CallEngine.CallSpec.OpeningAudio,
    Vxpipe.CallEngine.CallDefinition.Participant => Vxpipe.CallEngine.CallSpec.Participant,
    Vxpipe.CallEngine.CallDefinition.ToolSelection => Vxpipe.CallEngine.CallSpec.ToolSelection,
    Vxpipe.CallEngine.CallDefinition.ToolVisibility => Vxpipe.CallEngine.CallSpec.ToolVisibility,
    Vxpipe.CallEngine.CallDefinition.TransferHistory =>
      Vxpipe.CallEngine.CallSpec.TransferHistory,
    Vxpipe.CallEngine.CallDefinition.TransferPolicy => Vxpipe.CallEngine.CallSpec.TransferPolicy,
    Vxpipe.CallEngine.CallDefinition.VariablePermissions =>
      Vxpipe.CallEngine.CallSpec.VariablePermissions,
    Vxpipe.CallEngine.CallDefinition.VariableSchema => Vxpipe.CallEngine.CallSpec.VariableSchema,
    Vxpipe.CallEngine.CallDefinition.VariableSection =>
      Vxpipe.CallEngine.CallSpec.VariableSection,
    Vxpipe.CallEngine.CallDefinition.WaitSounds => Vxpipe.CallEngine.CallSpec.WaitSounds,
    Vxpipe.CallEngine.DefinitionCompiler => Vxpipe.CallEngine.CallSpecCompiler,
    Vxpipe.CallEngine.ResolvedCallPlan => Vxpipe.CallEngine.ResolvedCallPlan,
    Vxpipe.CallEngine.ResolvedCallPlan.CallVariables =>
      Vxpipe.CallEngine.ResolvedCallPlan.CallVariables,
    Vxpipe.CallEngine.ResolvedCallPlan.Capabilities =>
      Vxpipe.CallEngine.ResolvedCallPlan.Capabilities,
    Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy =>
      Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy,
    Vxpipe.CallEngine.ResolvedCallPlan.OpeningAudio =>
      Vxpipe.CallEngine.ResolvedCallPlan.OpeningAudio,
    Vxpipe.CallEngine.ResolvedCallPlan.Participant =>
      Vxpipe.CallEngine.ResolvedCallPlan.Participant,
    Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding =>
      Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding,
    Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility =>
      Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility,
    Vxpipe.CallEngine.ResolvedCallPlan.VariableSection =>
      Vxpipe.CallEngine.ResolvedCallPlan.VariableSection,
    Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding =>
      Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding,
    Vxpipe.CallEngine.Tool.ParticipantTransfer.Request =>
      Vxpipe.CallEngine.Tool.ParticipantTransfer.Request
  }

  @legacy_field_renames %{
    Vxpipe.CallEngine.ResolvedCallPlan => %{
      definition_id: :call_spec_id,
      definition_revision: :call_spec_revision
    },
    Vxpipe.CallEngine.CallDefinition.Participant => %{definition_key: :call_spec_key},
    Vxpipe.CallEngine.ResolvedCallPlan.Participant => %{definition_key: :call_spec_key},
    Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding => %{
      source_definition_key: :source_call_spec_key
    },
    Vxpipe.CallEngine.Tool.ParticipantTransfer.Request => %{
      source_definition_key: :source_call_spec_key,
      destination_definition_key: :destination_call_spec_key
    }
  }

  @spec encode(ResolvedCallPlan.t()) :: binary()
  def encode(%ResolvedCallPlan{} = plan), do: :erlang.term_to_binary(plan, [:deterministic])

  @spec decode(binary()) :: {:ok, ResolvedCallPlan.t()} | {:error, :invalid_stored_call_plan}
  def decode(encoded) when is_binary(encoded) do
    ResolvedCallPlan.ensure_data_loaded!()

    case encoded |> :erlang.binary_to_term([:safe]) |> normalize() do
      %ResolvedCallPlan{} = plan -> {:ok, Map.put_new(plan, :credential_bindings, nil)}
      _invalid -> {:error, :invalid_stored_call_plan}
    end
  rescue
    ArgumentError -> {:error, :invalid_stored_call_plan}
  end

  defp normalize(%{__struct__: module} = value) do
    normalized_module = Map.get(@legacy_struct_modules, module, module)
    field_renames = Map.get(@legacy_field_renames, module, %{})

    value
    |> Map.to_list()
    |> Enum.map(fn {key, nested} ->
      normalized_key = Map.get(field_renames, key, key)
      {normalized_key, normalize_struct_field(module, normalized_key, nested)}
    end)
    |> Map.new()
    |> Map.put(:__struct__, normalized_module)
  end

  defp normalize(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, normalize(nested)} end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)

  defp normalize(value), do: value

  defp normalize_struct_field(
         Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding,
         :targets,
         targets
       )
       when is_map(targets) do
    targets
    |> normalize()
    |> Map.new(fn {key, target} -> {key, normalize_transfer_target(target)} end)
  end

  defp normalize_struct_field(_module, _key, nested), do: normalize(nested)

  defp normalize_transfer_target(%{definition_key: key} = target) do
    target
    |> Map.put_new(:call_spec_key, key)
    |> Map.delete(:definition_key)
  end

  defp normalize_transfer_target(target), do: target
end
