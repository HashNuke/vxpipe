defmodule Vxpipe.AgentRuntime.IdentityProbe do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{ToolDescriptor, ToolRegistry}

  def measure(churn_count, offset \\ 0)

  def measure(churn_count, offset)
      when is_integer(churn_count) and churn_count > 0 and is_integer(offset) and offset >= 0 do
    {:ok, _applications} = Application.ensure_all_started(:vxpipe_agent_runtime)

    warmup_range = (offset + 1)..(offset + churn_count)
    measured_range = (offset + churn_count + 1)..(offset + 2 * churn_count)

    Enum.each(warmup_range, &churn_once!/1)
    _ = :code.all_loaded()
    atoms_before = :erlang.system_info(:atom_count)
    modules_before = loaded_modules()

    Enum.each(measured_range, &churn_once!/1)
    :erlang.garbage_collect()

    %{
      atom_growth: :erlang.system_info(:atom_count) - atoms_before,
      module_growth: MapSet.size(MapSet.difference(loaded_modules(), modules_before)),
      atomized_values: atomized_external_values(measured_range)
    }
  end

  defp churn_once!(index) do
    first = descriptor!(index, "primary")
    second = descriptor!(index, "secondary")

    {:ok, registry} = ToolRegistry.new([first, second])

    [first_projection, second_projection] = ToolRegistry.model_tools(registry)
    true = first_projection.name == first.name
    true = second_projection.name == second.name

    {:ok, ^first} =
      ToolRegistry.resolve(registry, first.name, %{"field-primary-#{index}" => "value"})

    {:ok, ^second} =
      ToolRegistry.resolve(registry, second.name, %{"field-secondary-#{index}" => "value"})
  end

  defp descriptor!(index, suffix) do
    field = "field-#{suffix}-#{index}"

    {:ok, descriptor} =
      ToolDescriptor.new(
        name: "alias-#{suffix}-#{index}",
        description: "Alias #{suffix} revision #{index}",
        input_schema: %{
          "type" => "object",
          "properties" => %{field => %{"type" => "string"}},
          "required" => [field],
          "additionalProperties" => false
        },
        binding: %{
          handler: Vxpipe.AgentRuntime.TestExecutor,
          binding_id: "binding-#{suffix}-#{index}"
        }
      )

    descriptor
  end

  defp atomized_external_values(range) do
    Enum.flat_map(range, fn index ->
      index
      |> external_values()
      |> Enum.reject(&atom_missing?/1)
    end)
  end

  defp external_values(index) do
    Enum.flat_map(["primary", "secondary"], fn suffix ->
      [
        "alias-#{suffix}-#{index}",
        "field-#{suffix}-#{index}",
        "binding-#{suffix}-#{index}"
      ]
    end)
  end

  defp atom_missing?(value) do
    _existing = String.to_existing_atom(value)
    false
  rescue
    ArgumentError -> true
  end

  defp loaded_modules do
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> MapSet.new()
  end
end
