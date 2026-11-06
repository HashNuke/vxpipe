defmodule Vxpipe.Console.IntegrationsDirectory.Page do
  @moduledoc "Validates public directory pages against the shipped schema and request identity."

  alias Vxpipe.Console.IntegrationsDirectory.Request

  @schema_path Path.expand(
                 "../../../../../../docs/development/integrations-directory.schema.json",
                 __DIR__
               )
  @external_resource @schema_path
  @schema @schema_path
          |> File.read!()
          |> JSON.decode!()
          |> JSV.build!(resolver: [], atoms: false, formats: true, warnings: :silent)

  def validate(page, request) do
    with {:ok, _validated} <- JSV.validate(page, @schema, cast: false),
         true <- page["resource"] == request.resource,
         true <- page["installation_version"] == Request.installation_version(),
         true <-
           is_nil(request.params["revision"]) or page["revision"] == request.params["revision"],
         true <- valid_query?(page, request),
         true <- valid_pagination?(page, request),
         true <- unique_items?(page["items"]),
         true <- supported_items?(page, request) do
      {:ok, page}
    else
      _invalid -> {:error, :invalid_page}
    end
  end

  defp valid_query?(%{"resource" => "categories"}, _request), do: true

  defp valid_query?(page, request) do
    page["query"] == %{
      "category" => request.params["category"],
      "q" => Map.get(request.params, "q", ""),
      "scope" => request.params["scope"]
    }
  end

  defp valid_pagination?(page, request) do
    pagination = page["pagination"]
    count = length(page["items"])

    pagination["limit"] == request.params["limit"] and count <= pagination["limit"] and
      (Map.has_key?(request.params, "cursor") or pagination["start_index"] in [0, 1]) and
      valid_range?(pagination, count)
  end

  defp valid_range?(pagination, 0) do
    pagination["total_items"] == 0 and pagination["start_index"] == 0 and
      pagination["end_index"] == 0 and is_nil(pagination["next_cursor"]) and
      is_nil(pagination["previous_cursor"])
  end

  defp valid_range?(pagination, count) do
    first = pagination["start_index"]
    last = pagination["end_index"]
    total = pagination["total_items"]

    first >= 1 and last == first + count - 1 and last <= total and
      first == 1 == is_nil(pagination["previous_cursor"]) and
      last == total == is_nil(pagination["next_cursor"])
  end

  defp unique_items?(items) do
    ids = Enum.map(items, &Map.fetch!(&1, "id"))
    length(ids) == MapSet.size(MapSet.new(ids))
  end

  defp supported_items?(%{"resource" => "categories"}, _request), do: true

  defp supported_items?(page, request) do
    Enum.all?(page["items"], fn item ->
      compatible_version?(item["minimum_vxpipe_version"], [:eq, :gt]) and
        compatible_version?(item["maximum_vxpipe_version_exclusive"], [:lt]) and
        installed_item?(item, request.params["scope"])
    end)
  end

  defp compatible_version?(nil, _comparisons), do: true

  defp compatible_version?(bound, comparisons) do
    case Version.parse(bound) do
      {:ok, version} -> Version.compare(Request.installation_version(), version) in comparisons
      :error -> false
    end
  end

  defp installed_item?(%{"kind" => "mcp", "connection" => connection}, scope),
    do: scope == "tenant" and valid_mcp_endpoint?(connection["endpoint"])

  defp installed_item?(%{"kind" => "provider", "connection" => connection}, _scope) do
    match?(
      {:ok, _module},
      Vxpipe.Providers.Registry.resolve_capability(connection["provider_id"], :credential)
    )
  end

  defp valid_mcp_endpoint?(endpoint) do
    with {:ok, %URI{scheme: "https", host: host, userinfo: nil, query: nil, fragment: nil} = uri} <-
           URI.new(endpoint) do
      is_binary(host) and host != "" and is_integer(uri.port) and uri.port in 1..65_535
    else
      _ -> false
    end
  end
end
