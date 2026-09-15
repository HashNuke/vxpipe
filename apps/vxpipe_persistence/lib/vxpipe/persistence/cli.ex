defmodule Vxpipe.Persistence.CLI do
  @moduledoc false

  alias Vxpipe.Calls.DefinitionRevision
  alias Vxpipe.Persistence.Repo

  def ensure_ready! do
    if Process.whereis(Repo) == nil do
      case Application.ensure_all_started(:vxpipe_persistence) do
        {:ok, _applications} -> :ok
        {:error, _reason} -> Mix.raise("could not start configured Vxpipe persistence")
      end
    end

    if Process.whereis(Repo) == nil do
      Mix.raise("database persistence is not configured; set VXPIPE_DB_URL or DATABASE_URL")
    end
  end

  def options!(arguments, switches, required) do
    arguments = normalize_string_arguments(arguments, switches)

    case OptionParser.parse(arguments, strict: switches) do
      {options, [], []} ->
        Enum.each(required, &required!(options, &1))
        options

      {_options, remaining, invalid} ->
        Mix.raise("invalid arguments: #{inspect(remaining ++ invalid)}")
    end
  end

  def scopes!(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn
      "admin" -> :admin
      "calls" -> :calls
      _invalid -> Mix.raise("scopes must contain only admin or calls")
    end)
    |> case do
      [] -> Mix.raise("at least one scope is required")
      scopes -> Enum.uniq(scopes)
    end
  end

  def scopes!(_value), do: Mix.raise("--scopes is required")

  def positive_integer!(value, option) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> Mix.raise("--#{option} must be a positive integer")
    end
  end

  def read_json_file!(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, value} when is_map(value) <- JSON.decode(contents) do
      value
    else
      _error -> Mix.raise("definition file must contain a readable JSON object")
    end
  end

  def output!(value), do: Mix.shell().info(JSON.encode!(value))

  def unwrap!({:ok, value}), do: value

  def unwrap!({:error, reason}) do
    Mix.raise("Vxpipe operation failed: #{format_reason(reason)}")
  end

  def unwrap_bootstrap!({:ok, tenant, issued}), do: {tenant, issued}

  def unwrap_bootstrap!({:error, reason}) do
    Mix.raise("Vxpipe operation failed: #{format_reason(reason)}")
  end

  def revision_summary(%DefinitionRevision{} = revision, include_source? \\ false) do
    summary = %{
      "definition_id" => revision.definition_id,
      "revision" => revision.revision,
      "schema_version" => revision.schema_version,
      "source_digest" => revision.source_digest,
      "validation_errors" => revision.validation_errors,
      "published" => not is_nil(revision.published_at),
      "published_at" => date_time(revision.published_at),
      "routes" => Enum.map(revision.routes, &route_summary/1)
    }

    if include_source? do
      summary
      |> Map.put("source", revision.source)
      |> Map.put("compiled_metadata", revision.compiled_metadata)
    else
      summary
    end
  end

  defp route_summary(route) do
    %{
      "participant_key" => route.key,
      "participant_ref" => route.participant_ref,
      "published" => not is_nil(route.published_at)
    }
  end

  defp date_time(nil), do: nil
  defp date_time(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp required!(options, key) do
    if Keyword.get(options, key) in [nil, ""] do
      key
      |> Atom.to_string()
      |> String.replace("_", "-")
      |> then(&Mix.raise("--#{&1} is required"))
    end
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason({reason, _details}) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(_reason), do: "unexpected failure"

  defp normalize_string_arguments(arguments, switches) do
    string_options =
      switches
      |> Enum.filter(fn {_key, type} -> type == :string end)
      |> Map.new(fn {key, _type} ->
        option = key |> Atom.to_string() |> String.replace("_", "-")
        {"--#{option}", true}
      end)

    do_normalize_arguments(arguments, string_options)
  end

  defp do_normalize_arguments([option, value | rest], string_options)
       when is_map_key(string_options, option) do
    ["#{option}=#{value}" | do_normalize_arguments(rest, string_options)]
  end

  defp do_normalize_arguments([argument | rest], string_options),
    do: [argument | do_normalize_arguments(rest, string_options)]

  defp do_normalize_arguments([], _string_options), do: []
end
