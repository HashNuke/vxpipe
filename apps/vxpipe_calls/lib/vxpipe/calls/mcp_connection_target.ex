defmodule Vxpipe.Calls.MCPConnectionTarget do
  @moduledoc "Binds a new connection's credentialless target and tenant duplicate lookup before protocol work."
  alias Vxpipe.Calls.{MCPDiscoveryProposal, Repositories}
  alias Vxpipe.MCP.StaticConfiguration

  @fields [:endpoint, :endpoint_identity, :directory_id, :directory_entry, :revision]
  @errors [
    :invalid_mcp_endpoint,
    :invalid_mcp_listing,
    :mcp_listing_unavailable,
    :invalid_oauth_issuer
  ]

  def resolve(port, repository, tenant, input, continuation) do
    with true <- available?(port, :resolve_target, 3),
         {operation, arity} = continuation,
         true <- available?(port, operation, arity),
         true <- available?(repository, :find_identity, 3) do
      case Repositories.call(port, :resolve_target, [tenant, public_input(input)]) do
        {:ok, target} ->
          if valid?(target, input), do: {:ok, target}, else: unavailable()

        {:error, reason} when reason in @errors ->
          {:error, reason}

        _ ->
          unavailable()
      end
    else
      _ -> unavailable()
    end
  end

  def lookup(repository, tenant, target, refresh) do
    identity = Map.take(target, [:endpoint_identity, :directory_id])
    result = Repositories.call(repository, :find_identity, [tenant, identity])

    with :ok <- refresh.() do
      duplicate(result, tenant, target)
    end
  end

  def checked?(connection, target) do
    connection[:endpoint] == target.endpoint and
      connection[:endpoint_identity] == target.endpoint_identity and
      connection[:directory_id] == target.directory_id and
      connection[:directory_entry] == target.directory_entry and
      (is_nil(target.directory_entry) or connection[:server_name] == target.directory_entry["name"])
  end

  def prepared?(prepared, target) do
    prepared.attributes[:resource] == target.endpoint and
      prepared.attributes[:draft_revision] == target.revision and
      prepared.secrets["directory_entry"] == target.directory_entry
  end

  defp public_input(%{"listing" => _} = input), do: Map.take(input, ~w(listing revision issuer))
  defp public_input(input), do: Map.take(input, ~w(endpoint revision issuer))

  defp valid?(%{endpoint: endpoint, endpoint_identity: endpoint, revision: revision} = target, input) do
    Map.keys(target) -- @fields == [] and
      StaticConfiguration.endpoint(endpoint) == {:ok, endpoint} and
      revision == input["revision"] and bound?(target, input)
  end

  defp valid?(_, _), do: false

  defp bound?(%{directory_entry: %{} = entry, directory_id: identity} = target, %{"listing" => _} = input) do
    is_binary(entry["directory_id"]) and is_binary(entry["integration_id"]) and
      identity == entry["directory_id"] <> "/" <> entry["integration_id"] and
      MCPDiscoveryProposal.matches?(
        %{revision: target.revision, endpoint: target.endpoint, listing: entry},
        Map.put(input, "revision", target.revision)
      )
  end

  defp bound?(%{directory_entry: nil, directory_id: nil, endpoint: endpoint}, %{"endpoint" => input} = proposal) do
    not Map.has_key?(proposal, "listing") and StaticConfiguration.endpoint(input) == {:ok, endpoint}
  end

  defp bound?(_, _), do: false

  defp duplicate({:ok, nil}, _tenant, _target), do: :ok

  defp duplicate({:ok, %{tenant_key: tenant, id: id, generation: generation} = record}, tenant, target)
       when is_binary(id) and byte_size(id) in 1..128 and is_integer(generation) and
              generation > 0 and generation <= 9_007_199_254_740_991 do
    matching? =
      record[:endpoint_identity] == target.endpoint_identity or
        (not is_nil(target.directory_id) and record[:directory_id] == target.directory_id)

    if matching? and Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, id) do
      case record[:status] do
        "connected" -> {:error, {:mcp_connection_exists, id}}
        "revoked" -> {:error, {:mcp_reconnect_required, %{id: id, generation: generation}}}
        _ -> unavailable()
      end
    else
      unavailable()
    end
  end

  defp duplicate(_, _, _), do: unavailable()

  defp available?({module, _}, operation, arity),
    do: Code.ensure_loaded?(module) and function_exported?(module, operation, arity)

  defp unavailable, do: {:error, :mcp_connections_unavailable}
end
