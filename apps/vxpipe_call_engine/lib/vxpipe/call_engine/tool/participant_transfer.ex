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

    parameters =
      if Enum.any?(targets, fn {_definition_key, target} -> target.reason_required end) do
        %{"oneOf" => Enum.map(targets, &target_parameters/1)}
      else
        ordinary_parameters(targets)
      end

    %Definition{
      name: "transfer",
      description: "Transfer the caller to one permitted agent participant.",
      parameters: parameters
    }
  end

  defp ordinary_parameters(targets) do
    %{
      "type" => "object",
      "properties" => %{
        "destination" => %{
          "type" => "string",
          "oneOf" => Enum.map(targets, &destination_choice/1)
        }
      },
      "required" => ["destination"],
      "additionalProperties" => false
    }
  end

  defp target_parameters({_definition_key, %{reason_required: true}} = target) do
    %{
      "type" => "object",
      "properties" => %{
        "destination" => destination_choice(target),
        "reason" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 1_024,
          "description" => "Explain why the caller is being transferred."
        }
      },
      "required" => ["destination", "reason"],
      "additionalProperties" => false
    }
  end

  defp target_parameters(target) do
    %{
      "type" => "object",
      "properties" => %{"destination" => destination_choice(target)},
      "required" => ["destination"],
      "additionalProperties" => false
    }
  end

  defp destination_choice({definition_key, target}) do
    choice = %{"const" => definition_key}

    case target.description do
      description when is_binary(description) -> Map.put(choice, "description", description)
      nil -> choice
    end
  end

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
