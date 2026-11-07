defmodule Vxpipe.Calls.MCPDiscoveryProposal do
  @moduledoc "Credentialless discovery input and draft/entry identity at the authorized port boundary."

  def validate(
        %{"connection_id" => id, "generation" => generation, "revision" => revision} = input
      )
      when is_binary(id) and byte_size(id) in 1..128 and is_integer(generation) and generation > 0 and
             is_binary(revision) and byte_size(revision) in 1..128 do
    if Map.keys(input) -- ~w(connection_id generation revision issuer) == [] and
         valid_issuer?(input) and
         Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, id) and String.valid?(revision),
       do: :ok,
       else: {:error, :invalid_mcp_preflight}
  end

  def validate(%{"listing" => listing, "revision" => revision} = input)
      when is_map(listing) and is_binary(revision) and byte_size(revision) in 1..128 do
    if Map.keys(input) -- ~w(listing revision issuer) == [] and valid_issuer?(input) and
         byte_size(JSON.encode!(listing)) <= 8192,
       do: :ok,
       else: {:error, :invalid_mcp_preflight}
  rescue
    _ -> {:error, :invalid_mcp_preflight}
  end

  def validate(%{"endpoint" => endpoint, "revision" => revision} = input)
      when is_binary(endpoint) and byte_size(endpoint) in 1..2048 and
             is_binary(revision) and byte_size(revision) in 1..128 do
    if Map.keys(input) -- ~w(endpoint revision issuer) == [] and valid_issuer?(input),
      do: :ok,
      else: {:error, :invalid_mcp_preflight}
  end

  def validate(_input), do: {:error, :invalid_mcp_preflight}

  def matches?(
        %{revision: revision, endpoint: endpoint, listing: snapshot},
        %{
          "revision" => revision,
          "listing" => %{
            "directory_id" => directory,
            "integration_id" => integration,
            "entry_revision" => entry_revision
          }
        }
      )
      when is_binary(endpoint) and byte_size(endpoint) in 1..2048 and is_map(snapshot) and
             is_binary(directory) and is_binary(integration) and is_integer(entry_revision) do
    snapshot["endpoint"] == endpoint and
      snapshot["directory_id"] == directory and
      snapshot["integration_id"] == integration and
      snapshot["revision"] == entry_revision
  end

  def matches?(
        %{revision: revision, endpoint: endpoint},
        %{"revision" => revision, "endpoint" => endpoint}
      ),
      do: true

  def matches?(_result, _input), do: false

  defp valid_issuer?(input),
    do:
      not Map.has_key?(input, "issuer") or
        (is_binary(input["issuer"]) and byte_size(input["issuer"]) in 1..2048)
end
