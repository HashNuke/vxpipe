defmodule Vxpipe.Persistence.MCP.DirectoryEntry do
  @moduledoc "Validates the public accepted listing snapshot and its immutable stored binding."

  @required ~w(directory_id integration_id revision name endpoint authentication)
  @optional ~w(setup_notes setup_url documentation_url)
  @methods %{
    "none" => "none",
    "bearer" => "bearer",
    "basic" => "basic",
    "api_key" => "headers",
    "oauth2" => "oauth"
  }

  def bind(attributes, saved) do
    entry = Map.get(attributes, :directory_entry, saved)

    cond do
      saved != nil and saved != entry ->
        {:error, :invalid_mcp_configuration}

      is_nil(entry) ->
        {:ok, attributes}

      valid?(entry) and bound?(entry, attributes) ->
        {:ok,
         attributes |> Map.put(:directory_entry, entry) |> Map.put(:server_name, entry["name"])}

      true ->
        {:error, :invalid_mcp_configuration}
    end
  end

  def name(nil, reported), do: reported
  def name(%{"name" => name}, _reported), do: name

  defp bound?(entry, attributes) do
    attributes[:directory_id] == entry["directory_id"] <> "/" <> entry["integration_id"] and
      attributes[:endpoint] == entry["endpoint"] and
      attributes[:endpoint_identity] == entry["endpoint"] and
      attributes[:auth_method] == @methods[entry["authentication"]["type"]]
  end

  defp valid?(entry) when is_map(entry) and not is_struct(entry) do
    Map.keys(entry) -- (@required ++ @optional) == [] and
      Enum.all?(@required, &Map.has_key?(entry, &1)) and
      byte_size(JSON.encode!(entry)) <= 65_536 and
      identifier?(entry["directory_id"]) and identifier?(entry["integration_id"]) and
      is_integer(entry["revision"]) and entry["revision"] > 0 and
      text?(entry["name"], 100) and endpoint?(entry["endpoint"]) and
      recipe?(entry["authentication"]) and optional_fields?(entry)
  rescue
    _ -> false
  end

  defp valid?(_entry), do: false

  defp optional_fields?(entry) do
    (not Map.has_key?(entry, "setup_notes") or text?(entry["setup_notes"], 1000)) and
      Enum.all?(~w(setup_url documentation_url), fn key ->
        not Map.has_key?(entry, key) or link?(entry[key])
      end)
  end

  defp recipe?(%{"type" => type} = recipe) when type in ~w(none bearer basic),
    do: map_size(recipe) == 1

  defp recipe?(%{"type" => "api_key", "header_name" => header} = recipe),
    do:
      map_size(recipe) == 2 and is_binary(header) and byte_size(header) in 1..128 and
        Regex.match?(~r/\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\z/, header)

  defp recipe?(%{"type" => "oauth2", "registration" => registration} = recipe) do
    scopes = Map.get(recipe, "scopes", [])

    Map.keys(recipe) -- ~w(type registration scopes) == [] and
      registration in ~w(discover cimd dcr preregistered) and is_list(scopes) and
      length(scopes) <= 64 and length(Enum.uniq(scopes)) == length(scopes) and
      Enum.all?(scopes, fn scope ->
        is_binary(scope) and byte_size(scope) in 1..256 and
          Regex.match?(~r/\A[\x21\x23-\x5b\x5d-\x7e]+\z/, scope)
      end)
  end

  defp recipe?(_recipe), do: false

  defp identifier?(value),
    do:
      is_binary(value) and byte_size(value) in 1..64 and
        Regex.match?(~r/\A[a-z][a-z0-9-]*\z/, value)

  defp text?(value, limit),
    do: is_binary(value) and String.valid?(value) and String.length(value) in 1..limit

  defp endpoint?(value) do
    with true <- link?(value),
         {:ok, %URI{query: nil, fragment: nil}} <- URI.new(value),
         do: true,
         else: (_ -> false)
  end

  defp link?(value) when is_binary(value) and byte_size(value) in 1..2048 do
    with true <- String.valid?(value) and not Regex.match?(~r/[\x00-\x20\x7f]/, value),
         {:ok, %URI{scheme: "https", host: host, port: port, userinfo: nil}} <- URI.new(value) do
      is_binary(host) and host != "" and port in 1..65_535
    else
      _ -> false
    end
  end

  defp link?(_value), do: false
end
