defmodule Vxpipe.Console.IntegrationsDirectory.Inventory do
  @moduledoc "Authorized local connection status joined to public integration listings."

  alias Vxpipe.Calls.UserAuthorization
  alias Vxpipe.Console.IntegrationsDirectory.{Cache, Listing, NativeCatalog, Request}

  @outages [
    :unavailable,
    :timeout,
    :rate_limited,
    :invalid_page,
    :invalid_response,
    :response_too_large,
    :unsupported_version,
    :invalid_version,
    :busy,
    :unexpected_status
  ]

  def list(principal, scope, params, options \\ []) do
    with {:ok, directory} <- local_directory(principal, scope, options),
         {:ok, mcps} <- local_mcps(principal, scope, options),
         {:ok, request} <-
           Request.build(:integrations, Map.put(params, "scope", public_scope(scope))) do
      bindings = Enum.map(directory.bindings, &binding_projection(&1, principal, scope))

      context = %{
        tenant: directory.tenant,
        connections: bindings,
        mcp_connections: mcps,
        installation_version: Request.installation_version(),
        can_connect_native: can_write_credentials?(principal, scope),
        can_connect_mcp: scope != :platform and can_write?(principal, scope)
      }

      if request.params["category"] == "connected" do
        local =
          NativeCatalog.items()
          |> join(bindings, context.can_connect_native)
          |> Enum.filter(&(&1["connections"] != []))

        {:ok,
         Map.merge(context, %{
           directory_status: :local,
           local_items: local ++ Enum.map(mcps, &mcp_item/1),
           page: nil,
           fallback_items: []
         })}
      else
        browse(request.params, context, options)
      end
    end
  end

  defp local_directory(principal, scope, options) do
    case Vxpipe.Calls.list_operator_service_bindings(
           principal,
           scope,
           Keyword.get(options, :calls_options, [])
         ) do
      {:ok, directory} ->
        {:ok, directory}

      {:error, reason} when reason in [:forbidden, :tenant_not_found, :invalid_tenant_key] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :connection_status_unavailable}
    end
  end

  defp browse(params, context, options) do
    fetcher = Keyword.get(options, :fetcher, &Cache.fetch/2)

    case fetcher.(:integrations, params) do
      {:ok, %{body: page}} ->
        page = listing_references(page, params)

        page =
          Map.update!(
            page,
            "items",
            &join(
              &1,
              context.connections,
              context.can_connect_native,
              context.mcp_connections,
              context.can_connect_mcp
            )
          )

        {:ok,
         Map.merge(context, %{
           directory_status: :available,
           page: page,
           fallback_items: [],
           local_items: []
         })}

      {:error, reason} when reason in @outages ->
        items =
          NativeCatalog.items()
          |> filter_fallback(params)
          |> join(context.connections, context.can_connect_native)

        {:ok,
         Map.merge(context, %{
           directory_status: :unavailable,
           directory_error: reason,
           page: nil,
           fallback_items: items,
           local_items: []
         })}

      {:error, _reason} = error ->
        error
    end
  end

  defp listing_references(page, params) do
    Map.update!(page, "items", fn items ->
      Enum.map(items, fn
        %{"kind" => "mcp"} = item ->
          Map.put(item, "listing", Listing.reference(page, item, params))

        item ->
          item
      end)
    end)
  end

  defp join(items, bindings, can_connect, mcps \\ [], can_connect_mcp \\ false) do
    Enum.map(items, fn item ->
      connections =
        case item do
          %{"kind" => "provider", "connection" => %{"provider_id" => provider}} ->
            Enum.filter(bindings, &(&1.provider == provider))

          _mcp ->
            []
        end

      matched_mcps = matching_mcps(item, mcps)

      connect? =
        case item["kind"] do
          "provider" ->
            connections == [] and can_connect and item["availability"] != "retired"

          "mcp" ->
            matched_mcps == [] and can_connect_mcp and
              item["availability"] in ~w(available preview) and
              supported_recipe?(item["connection"])

          _ ->
            false
        end

      item
      |> Map.put("capabilities", native_capabilities(item))
      |> Map.put("connections", connections)
      |> Map.put("mcp_connections", matched_mcps)
      |> Map.put("can_connect", connect?)
    end)
  end

  defp supported_recipe?(%{"authentication" => %{"type" => type}})
       when type in ~w(none bearer basic),
       do: true

  defp supported_recipe?(%{"authentication" => %{"type" => "api_key", "header_name" => name}}) do
    match?(
      {:ok, _},
      Vxpipe.MCP.Authentication.headers(type: :custom_headers, headers: [{name, "validation"}])
    )
  end

  defp supported_recipe?(%{"authentication" => %{"type" => "oauth2", "registration" => method}})
       when method in ~w(discover cimd dcr preregistered),
       do: true

  defp supported_recipe?(_), do: false

  defp native_capabilities(%{"kind" => "provider", "connection" => %{"provider_id" => id}}),
    do: NativeCatalog.capabilities(id)

  defp native_capabilities(_item), do: []

  defp local_mcps(_principal, :platform, _options), do: {:ok, []}

  defp local_mcps(principal, tenant, options) do
    loader = Keyword.get(options, :mcp_loader, &Vxpipe.Calls.MCPConnections.list/3)

    case loader.(principal, tenant, Keyword.get(options, :calls_options, [])) do
      {:ok, records} ->
        {:ok, Enum.map(records, &Map.put(&1, :can_edit, can_write?(principal, tenant)))}

      {:error, _reason} ->
        {:error, :connection_status_unavailable}
    end
  end

  defp mcp_item(record) do
    %{
      "id" => "mcp-" <> record.id,
      "kind" => "mcp",
      "name" => record.server_name,
      "summary" => "",
      "connection" => %{"endpoint" => record.endpoint},
      "connections" => [],
      "mcp_connections" => [record],
      "can_connect" => false
    }
  end

  defp matching_mcps(
         %{"kind" => "mcp", "connection" => %{"endpoint" => endpoint}} = item,
         records
       ) do
    Enum.filter(records, fn record ->
      matches_directory?(record, item) or same_endpoint?(record.endpoint, endpoint)
    end)
  end

  defp matching_mcps(_item, _records), do: []

  defp matches_directory?(
         record,
         %{"listing" => %{"directory_id" => directory, "integration_id" => integration}}
       ),
       do: Map.get(record, :directory_id) == directory <> "/" <> integration

  defp matches_directory?(_record, _item), do: false

  defp same_endpoint?(left, right) do
    case {Vxpipe.MCP.StaticConfiguration.endpoint(left),
          Vxpipe.MCP.StaticConfiguration.endpoint(right)} do
      {{:ok, endpoint}, {:ok, endpoint}} -> true
      _invalid -> false
    end
  end

  defp filter_fallback(items, params) do
    query = params |> Map.get("q", "") |> String.downcase()
    category = params["category"]

    Enum.filter(items, fn item ->
      (category not in ["ai", "telephony"] or category in item["category_ids"]) and
        String.contains?(String.downcase(item["name"] <> " " <> item["summary"]), query)
    end)
  end

  defp binding_projection(binding, principal, scope) do
    owner = if binding.source == :platform, do: :platform, else: scope

    binding
    |> Map.take([
      :provider,
      :name,
      :status,
      :source,
      :credential_id,
      :saved_fields,
      :last_validated_at
    ])
    |> Map.put(:can_edit, can_write_credentials?(principal, owner))
  end

  defp can_write_credentials?(principal, scope),
    do: UserAuthorization.authorize_credential_write(principal, scope) == :ok

  defp can_write?(principal, :platform),
    do: UserAuthorization.authorize_installation(principal, "platform_services.write") == :ok

  defp can_write?(principal, scope),
    do: UserAuthorization.authorize_tenant_service_write(principal, scope) == :ok

  defp public_scope(:platform), do: "platform"
  defp public_scope(_tenant), do: "tenant"
end
