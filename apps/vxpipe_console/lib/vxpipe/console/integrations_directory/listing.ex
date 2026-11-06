defmodule Vxpipe.Console.IntegrationsDirectory.Listing do
  @moduledoc """
  Resolves an MCP listing reference using the existing public page cache.

  References carry lookup identity, never authoritative connection configuration.
  Callers must authorize the tenant operation before resolving a new proposal.
  Saved connections and in-flight OAuth attempts use their accepted snapshot,
  without looking up the directory again.
  """

  alias Vxpipe.Console.IntegrationsDirectory.{Cache, Page, Request}
  alias Vxpipe.MCP.{Authentication, StaticConfiguration}

  @reference_keys ~w(directory_id integration_id entry_revision page)
  @setup_fields ~w(setup_notes setup_url documentation_url)

  def reference(page, item, params) do
    {:ok, request} = Request.build(:integrations, Map.put(params, "scope", "tenant"))

    %{
      "directory_id" => Map.fetch!(page, "directory_id"),
      "integration_id" => Map.fetch!(item, "id"),
      "entry_revision" => Map.fetch!(item, "revision"),
      "page" => request.params
    }
  end

  def resolve(reference, options \\ []) do
    with {:ok, request} <- lookup_request(reference) do
      fetcher = Keyword.get(options, :fetcher, &Cache.fetch/2)
      resolve_page(fetcher, request, reference)
    end
  end

  defp lookup_request(
         %{
           "directory_id" => directory,
           "integration_id" => integration,
           "entry_revision" => revision,
           "page" => params
         } = reference
       )
       when is_map(params) and is_integer(revision) and revision > 0 do
    with true <- Map.keys(reference) -- @reference_keys == [],
         true <- identifier?(directory) and identifier?(integration),
         true <- Map.get(params, "scope", "tenant") == "tenant",
         true <- byte_size(JSON.encode!(reference)) <= 8192,
         {:ok, request} <- Request.build(:integrations, params) do
      {:ok, request}
    else
      _ -> {:error, :invalid_mcp_listing}
    end
  rescue
    _ -> {:error, :invalid_mcp_listing}
  end

  defp lookup_request(_reference), do: {:error, :invalid_mcp_listing}

  defp resolve_page(fetcher, request, reference) do
    with {:ok, %{body: body}} <- fetcher.(:integrations, request.params),
         {:ok, page} <- Page.validate(body, request),
         true <- page["directory_id"] == reference["directory_id"],
         %{"kind" => "mcp"} = item <-
           Enum.find(page["items"], &(&1["id"] == reference["integration_id"])),
         true <- item["revision"] == reference["entry_revision"],
         true <- item["availability"] in ~w(available preview),
         {:ok, snapshot} <- snapshot(page["directory_id"], item) do
      {:ok, snapshot}
    else
      _ -> {:error, :mcp_listing_unavailable}
    end
  rescue
    _ -> {:error, :mcp_listing_unavailable}
  catch
    :exit, _ -> {:error, :mcp_listing_unavailable}
  end

  defp snapshot(directory, item) do
    connection = item["connection"]

    with {:ok, endpoint} <- StaticConfiguration.endpoint(connection["endpoint"]),
         {:ok, recipe} <- recipe(connection["authentication"]),
         true <- Enum.all?(~w(setup_url documentation_url), &safe_link?(item[&1])) do
      {:ok,
       item
       |> Map.take(@setup_fields)
       |> Map.merge(%{
         "directory_id" => directory,
         "integration_id" => item["id"],
         "revision" => item["revision"],
         "name" => item["name"],
         "endpoint" => endpoint,
         "authentication" => recipe
       })}
    end
  end

  defp recipe(%{"type" => type}) when type in ~w(none bearer basic),
    do: {:ok, %{"type" => type}}

  defp recipe(%{"type" => "api_key", "header_name" => name}) do
    with {:ok, _headers} <-
           Authentication.headers(type: :custom_headers, headers: [{name, "validation"}]) do
      {:ok, %{"type" => "api_key", "header_name" => name}}
    end
  end

  defp recipe(%{"type" => "oauth2", "registration" => registration} = recipe)
       when registration in ~w(discover cimd dcr preregistered) do
    if Enum.all?(Map.get(recipe, "scopes", []), &scope?/1),
      do: {:ok, Map.take(recipe, ~w(type registration scopes))},
      else: {:error, :invalid_recipe}
  end

  defp recipe(_recipe), do: {:error, :invalid_recipe}

  defp scope?(scope), do: Regex.match?(~r/\A[\x21\x23-\x5b\x5d-\x7e]+\z/, scope)

  defp safe_link?(nil), do: true

  defp safe_link?(value) do
    with {:ok, %URI{scheme: "https", host: host, port: port, userinfo: nil}} <- URI.new(value) do
      is_binary(host) and host != "" and port in 1..65_535
    else
      _ -> false
    end
  end

  defp identifier?(value),
    do:
      is_binary(value) and byte_size(value) <= 64 and Regex.match?(~r/\A[a-z][a-z0-9-]*\z/, value)
end
