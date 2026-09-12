defmodule Vxpipe.CallEngine.Tool.ParticipantTransfer do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.Definition
  alias Vxpipe.CallEngine.Tool.{Context, PlatformResult}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.{Binding, Request}

  @spec definition(Binding.t()) :: Definition.t()
  def definition(%Binding{} = binding) do
    targets =
      binding.targets
      |> Enum.sort_by(fn {definition_key, _target} -> definition_key end)

    %Definition{
      name: "transfer",
      description: "Transfer the caller to one permitted participant.",
      parameters: parameters(targets)
    }
  end

  defp parameters(targets) do
    required_reason_targets =
      Enum.filter(targets, fn {_definition_key, target} -> target.reason_required end)

    parameters = %{
      "type" => "object",
      "properties" => %{
        "destination" => destination_schema(targets)
      },
      "required" => ["destination"],
      "additionalProperties" => false
    }

    add_reason(
      parameters,
      required_reason_targets,
      length(required_reason_targets) == length(targets)
    )
  end

  defp add_reason(parameters, [], _required_for_every_target?), do: parameters

  defp add_reason(parameters, required_targets, required_for_every_target?) do
    destination_keys =
      Enum.map(required_targets, fn {definition_key, _target} -> definition_key end)

    reason = %{
      "type" => "string",
      "minLength" => 1,
      "maxLength" => 1_024,
      "description" =>
        "Required for #{destination_label(destination_keys)}. Explain why the caller is being transferred."
    }

    parameters = put_in(parameters, ["properties", "reason"], reason)

    if required_for_every_target? do
      Map.put(parameters, "required", ["destination", "reason"])
    else
      parameters
    end
  end

  defp destination_label([definition_key]), do: "destination #{definition_key}"
  defp destination_label(definition_keys), do: "destinations #{Enum.join(definition_keys, ", ")}"

  defp destination_schema(targets) do
    label = if match?([_target], targets), do: "destination", else: "destinations"

    %{
      "type" => "string",
      "enum" => Enum.map(targets, fn {definition_key, _target} -> definition_key end),
      "description" =>
        "Permitted #{label}: " <> Enum.map_join(targets, ", ", &describe_target/1) <> "."
    }
  end

  defp describe_target({definition_key, %{description: description}})
       when is_binary(description),
       do: "#{definition_key} (#{description})"

  defp describe_target({definition_key, _target}), do: definition_key

  @spec execute(Binding.t(), map(), Context.t()) ::
          {:ok, PlatformResult.t()} | {:error, :tool_failed}
  def execute(%Binding{} = binding, arguments, %Context{} = context) when is_map(arguments) do
    with {:ok, request} <- Request.new(binding, arguments, context),
         {:ok, result} <- Vxpipe.CallEngine.RoomAuthority.transfer(request) do
      {:ok, %PlatformResult{effect: :participant_transfer_committed, result: result}}
    else
      _rejected_or_unavailable -> {:error, :tool_failed}
    end
  end
end
