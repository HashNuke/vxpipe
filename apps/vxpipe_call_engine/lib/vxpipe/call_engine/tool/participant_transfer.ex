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
      |> Enum.map(fn {definition_key, target} ->
        choice = %{"const" => definition_key}

        case target.description do
          description when is_binary(description) -> Map.put(choice, "description", description)
          nil -> choice
        end
      end)

    %Definition{
      name: "transfer",
      description: "Transfer the caller to one permitted agent participant.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "destination" => %{
            "type" => "string",
            "oneOf" => targets
          }
        },
        "required" => ["destination"],
        "additionalProperties" => false
      }
    }
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
