defmodule Vxpipe.Console.IntegrationsDirectory.NativeCatalog do
  @moduledoc "Installed native credential adapters with app-owned presentation metadata."
  alias Vxpipe.Providers.Registry

  @catalog_path Path.expand("../../../../assets/src/admin/setupCatalog.json", __DIR__)
  @external_resource @catalog_path
  @catalog @catalog_path |> File.read!() |> JSON.decode!() |> Map.fetch!("providers")

  def items do
    @catalog
    |> Enum.filter(&installed?/1)
    |> Enum.map(&entry/1)
    |> Enum.sort_by(&{String.downcase(&1["name"]), &1["id"]})
  end

  def capabilities(provider_id) do
    Registry.catalog()
    |> Map.get(provider_id, [])
    |> Enum.filter(&(&1 in [:stt, :llm, :tts, :sts, :telephony]))
  end

  defp installed?(provider) do
    match?({:ok, _}, Registry.resolve_capability(provider["id"], :credential))
  end

  defp entry(provider) do
    id = provider["id"]
    category = if :telephony in Map.fetch!(Registry.catalog(), id), do: "telephony", else: "ai"

    %{
      "id" => "provider-" <> String.replace(id, "_", "-"),
      "kind" => "provider",
      "name" => provider["name"],
      "summary" => provider["description"],
      "category_ids" => [category],
      "availability" => "available",
      "connection" => %{"type" => "builtin", "provider_id" => id}
    }
  end
end
