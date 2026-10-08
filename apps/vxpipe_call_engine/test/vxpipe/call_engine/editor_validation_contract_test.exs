defmodule Vxpipe.CallEngine.EditorValidationContractTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.CallSpec

  @fixture_path Path.expand(
                  "../../../../../examples/contracts/call-spec-editor-validation.json",
                  __DIR__
                )
  @external_resource @fixture_path
  @fixture @fixture_path |> File.read!() |> JSON.decode!()

  for scenario <- @fixture["cases"] do
    @scenario scenario
    test "editor path contract: #{@scenario["name"]}" do
      source =
        Enum.reduce(
          @scenario["changes"],
          Map.fetch!(@fixture["bases"], @scenario["base"]),
          &change/2
        )

      result = CallSpec.new(source, resource_id: "editor", revision: 1)

      case @scenario["expected_path"] do
        nil ->
          assert {:ok, _spec} = result

        path ->
          assert {:error, error} = result
          assert error.details["path"] == path
      end
    end
  end

  defp change(%{"path" => path} = change, source) do
    keys = Enum.map(path, &Access.key(&1, %{}))

    if change["delete"] do
      {_removed, updated} = pop_in(source, keys)
      updated
    else
      value =
        if change["repeat"],
          do: String.duplicate(change["value"], change["repeat"]),
          else: change["value"]

      put_in(source, keys, value)
    end
  end
end
