defmodule Vxpipe.Calls.MCPOAuthProposal do
  @moduledoc "Binds listed OAuth proposals, accepted snapshots and protocol port results."
  alias Vxpipe.Calls.MCPDiscoveryProposal

  @listed_fields ~w(listing endpoint auth_method revision issuer credentials initial_access_token)

  def validate(%{"listing" => reference, "revision" => revision} = input)
      when is_map(reference) and is_binary(revision) and byte_size(revision) in 1..128 do
    if Map.keys(input) -- @listed_fields == [] and String.valid?(revision) and
         is_map(Map.get(input, "credentials", %{})) and
         byte_size(JSON.encode!(reference)) <= 8192 and byte_size(JSON.encode!(input)) <= 81_920,
       do: :ok,
       else: {:error, :invalid_oauth_preparation}
  rescue
    _ -> {:error, :invalid_oauth_preparation}
  end

  def validate(%{"listing" => _}), do: {:error, :invalid_oauth_preparation}
  def validate(%{}), do: :ok
  def validate(_), do: {:error, :invalid_oauth_preparation}

  def prepared?(prepared, %{"listing" => _} = input) do
    entry = prepared.secrets["directory_entry"]

    oauth_entry?(entry, prepared.attributes[:resource]) and
      MCPDiscoveryProposal.matches?(
        %{
          revision: prepared.attributes[:draft_revision],
          endpoint: prepared.attributes[:resource],
          listing: entry
        },
        input
      )
  end

  def prepared?(prepared, _input), do: not Map.has_key?(prepared.secrets, "directory_entry")

  def saved_input(input, %{directory_entry: %{} = entry} = connection) when is_map(input) do
    if Map.keys(input) -- List.delete(@listed_fields, "listing") == [] and
         oauth_entry?(entry, connection.endpoint) and connection.auth_method == "oauth",
       do: {:ok, Map.put(input, "endpoint", connection.endpoint)},
       else: {:error, :invalid_oauth_reconnect}
  end

  def saved_input(input, _connection) when is_map(input) do
    if Map.has_key?(input, "listing") or Map.has_key?(input, "directory_entry"),
      do: {:error, :invalid_oauth_reconnect},
      else: {:ok, input}
  end

  def saved_input(_, _), do: {:error, :invalid_oauth_reconnect}

  def saved_prepared?(prepared, input, %{directory_entry: %{} = entry, endpoint: endpoint}) do
    prepared.secrets["directory_entry"] == entry and
      prepared.attributes[:resource] == endpoint and
      prepared.attributes[:draft_revision] == input["revision"]
  end

  def saved_prepared?(prepared, input, _), do: prepared?(prepared, input)

  def completed?(connection, claimed) do
    entry = claimed.secrets["directory_entry"]
    connection[:endpoint] == claimed.attempt[:resource] and completed_entry?(connection, entry)
  end

  defp completed_entry?(connection, nil), do: is_nil(connection[:directory_entry])

  defp completed_entry?(connection, entry) do
    oauth_entry?(entry, connection[:endpoint]) and
      connection[:directory_entry] == entry and
      connection[:directory_id] == entry["directory_id"] <> "/" <> entry["integration_id"] and
      connection[:server_name] == entry["name"]
  end

  defp oauth_entry?(
         %{
           "directory_id" => directory,
           "integration_id" => integration,
           "endpoint" => endpoint,
           "authentication" => %{"type" => "oauth2"}
         },
         endpoint
       )
       when is_binary(directory) and is_binary(integration) and is_binary(endpoint),
       do: true

  defp oauth_entry?(_, _), do: false
end
