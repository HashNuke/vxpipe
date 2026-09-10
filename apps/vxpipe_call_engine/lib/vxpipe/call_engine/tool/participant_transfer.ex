defmodule Vxpipe.CallEngine.Tool.ParticipantTransfer do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.Definition
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding

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
end
