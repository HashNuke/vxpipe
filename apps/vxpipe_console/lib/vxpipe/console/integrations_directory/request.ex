defmodule Vxpipe.Console.IntegrationsDirectory.Request do
  @moduledoc """
  Builds public directory requests from a closed set of non-private parameters.

  The directory origin is installation configuration, never browser input. The
  installation version comes from compiled OTP metadata, including in releases.
  """

  @default_origin "https://integrations-api-production-2803.up.railway.app"
  @category_keys ~w(limit cursor revision)
  @integration_keys ~w(limit cursor revision category q scope)

  def installation_version, do: Application.spec(:vxpipe_console, :vsn) |> to_string()

  def build(resource, params, origin \\ configured_origin())

  def build(resource, params, origin) when resource in [:categories, :integrations] do
    with {:ok, origin} <- validate_origin(origin),
         {:ok, params} <- normalize_params(resource, params) do
      {:ok,
       %{
         resource: Atom.to_string(resource),
         url: origin <> "/v1/" <> Atom.to_string(resource),
         params: params,
         headers: [
           {"accept", "application/json"},
           {"x-vxpipe-version", installation_version()}
         ]
       }}
    end
  end

  def build(_resource, _params, _origin), do: {:error, :invalid_resource}

  def validate_origin(origin) when is_binary(origin) do
    with {:ok, uri} <- URI.new(origin),
         %URI{scheme: "https", host: host, userinfo: nil, query: nil, fragment: nil} <- uri,
         true <- is_binary(host) and host != "",
         true <- uri.path in [nil, "", "/"],
         true <- is_integer(uri.port) and uri.port in 1..65_535 do
      {:ok, URI.to_string(%{uri | path: nil})}
    else
      _invalid -> {:error, :invalid_origin}
    end
  end

  def validate_origin(_origin), do: {:error, :invalid_origin}

  defp configured_origin do
    Application.get_env(:vxpipe_console, :integrations_directory_origin, @default_origin)
  end

  defp normalize_params(resource, params) when is_map(params) do
    keys = if resource == :categories, do: @category_keys, else: @integration_keys
    default_limit = if resource == :categories, do: 100, else: 20
    params = Map.put_new(params, "limit", default_limit)

    params =
      if resource == :integrations, do: Map.put_new(params, "scope", "tenant"), else: params

    if Enum.all?(params, fn {key, value} -> key in keys and valid_param?(key, value) end) do
      normalize_search(params)
    else
      {:error, :invalid_query}
    end
  end

  defp normalize_params(_resource, _params), do: {:error, :invalid_query}

  defp normalize_search(params) do
    query = params |> Map.get("q", "") |> String.trim()
    params = if query == "", do: Map.delete(params, "q"), else: Map.put(params, "q", query)

    if query != "" and Map.has_key?(params, "category"),
      do: {:error, :invalid_query},
      else: {:ok, params}
  end

  defp valid_param?("limit", value), do: is_integer(value) and value in 1..100
  defp valid_param?("scope", value), do: value in ["tenant", "platform"]
  defp valid_param?("q", value), do: is_binary(value) and String.length(String.trim(value)) <= 200

  defp valid_param?("category", value),
    do:
      is_binary(value) and byte_size(value) <= 64 and
        Regex.match?(~r/^[a-z][a-z0-9-]{0,63}$/, value)

  defp valid_param?(key, value) when key in ["cursor", "revision"],
    do: is_binary(value) and byte_size(value) in 1..2048

  defp valid_param?(_key, _value), do: false
end
