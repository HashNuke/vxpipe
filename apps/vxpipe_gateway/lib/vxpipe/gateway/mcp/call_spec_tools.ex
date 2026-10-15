defmodule Vxpipe.Gateway.MCP.CallSpecTools do
  @moduledoc "MCP schemas and projections over the shared call-spec operations."

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{CallSpecErrors, ProviderCatalogErrors}
  alias Vxpipe.Gateway.{CallSpecJSON, CatalogPage}

  @tenant %{tenant_key: %{type: "string", pattern: "^[A-Za-z0-9_-]{16}$"}}
  @identity Map.put(@tenant, :call_spec_id, %{
              type: "string",
              minLength: 1,
              maxLength: 128,
              pattern: "^[^\\x00\\r\\n]+$"
            })
  @revision %{type: "integer", minimum: 1, maximum: 2_147_483_647}
  @paging %{
    page: %{type: "integer", minimum: 1, maximum: 2_147_483_647, default: 1},
    page_size: %{type: "integer", minimum: 1, maximum: 50, default: 25}
  }
  @catalog Map.merge(@tenant, @paging)
           |> Map.put(:capability, %{
             type: "string",
             enum:
               ~w(speech_to_text output_speech_to_text text_to_speech speech_to_speech model_inference)
           })
  @write_names ~w(create_call_spec update_call_spec publish_call_spec_revision)
  @definitions [
    {"list_call_specs", "List a tenant's call specs with bounded pagination.",
     Map.merge(@tenant, @paging), ["tenant_key"]},
    {"get_call_spec",
     "Read portable source and revision metadata; defaults to the latest saved revision.",
     Map.put(@identity, :revision, @revision), ["tenant_key", "call_spec_id"]},
    {"create_call_spec",
     "Save a new draft with a server-generated ID. Does not publish or start a call.",
     Map.put(@tenant, :call_spec_definition, %{type: "object"}),
     ["tenant_key", "call_spec_definition"]},
    {"update_call_spec",
     "Append a complete source replacement as a draft revision of an existing spec. Does not publish.",
     Map.put(@identity, :call_spec_definition, %{type: "object"}),
     ["tenant_key", "call_spec_id", "call_spec_definition"]},
    {"publish_call_spec_revision",
     "Explicitly publish a saved, valid revision. Does not start a call.",
     Map.put(@identity, :revision, @revision), ["tenant_key", "call_spec_id", "revision"]},
    {"list_providers",
     "List installed providers and public credential availability for a capability.", @catalog,
     ["tenant_key", "capability"]},
    {"list_provider_models", "List public models and voice options without calling a provider.",
     Map.put(@catalog, :provider, %{type: "string", minLength: 1, maxLength: 128}),
     ["tenant_key", "provider", "capability"]}
  ]
  @tools Enum.map(@definitions, fn {name, description, properties, required} ->
           read? = name not in @write_names

           %{
             name: name,
             description: description,
             inputSchema: %{
               type: "object",
               additionalProperties: false,
               properties: properties,
               required: required
             },
             annotations: %{
               readOnlyHint: read?,
               destructiveHint: not read?,
               idempotentHint: read?,
               openWorldHint: false
             }
           }
         end)

  def names, do: Enum.map(@tools, & &1.name)

  def list(actor),
    do: Enum.filter(@tools, &(Calls.authorize_call_specs(actor, action(&1.name)) == :ok))

  def authorize(actor, name, arguments) do
    with {:ok, arguments} <- validate(name, arguments) do
      case Calls.authorize_call_specs(actor, action(name)) do
        :ok -> {:ok, arguments}
        {:error, _reason} -> {:error, :forbidden}
      end
    end
  end

  def call(actor, "list_call_specs", args, options) do
    paging = [page: args["page"], limit: args["page_size"]]

    with {:ok, page} <-
           Calls.list_operator_call_specs(actor, args["tenant_key"], paging ++ options) do
      projected = CallSpecJSON.page(page)

      items =
        Enum.map(
          projected.call_specs,
          &%{
            call_spec_id: &1.id,
            latest_revision: &1.latest_revision,
            published_revision: &1.published_revision
          }
        )

      {:ok, %{items: items, pagination: projected.pagination}}
    end
  end

  def call(actor, "get_call_spec", args, options) do
    with {:ok, fetched} <-
           Calls.fetch_operator_call_spec(
             actor,
             args["tenant_key"],
             args["call_spec_id"],
             Keyword.put(options, :revision, args["revision"])
           ) do
      %{call_spec: spec} = CallSpecJSON.read(fetched)
      result = Map.take(spec, [:call_spec_id, :revision, :latest_revision, :published_revision])
      {:ok, Map.put(result, :call_spec_definition, spec.source)}
    end
  end

  def call(actor, name, args, options) when name in ["create_call_spec", "update_call_spec"] do
    options =
      if name == "update_call_spec",
        do: Keyword.put(options, :call_spec_id, args["call_spec_id"]),
        else: Keyword.delete(options, :call_spec_id)

    with {:ok, revision} <-
           Calls.save_authorized_call_spec(
             actor,
             args["tenant_key"],
             args["call_spec_definition"],
             options
           ) do
      {:ok,
       revision
       |> CallSpecJSON.write_revision()
       |> Map.take([:call_spec_id, :revision, :validation_errors])}
    end
  end

  def call(actor, "publish_call_spec_revision", args, options) do
    with {:ok, revision} <-
           Calls.publish_authorized_call_spec(
             actor,
             args["tenant_key"],
             args["call_spec_id"],
             args["revision"],
             options
           ),
         do: {:ok, %{call_spec_id: revision.call_spec_id, published_revision: revision.revision}}
  end

  def call(actor, "list_providers", args, options) do
    with {:ok, %{providers: providers}} <-
           Calls.list_providers(actor, args["tenant_key"], args["capability"], options),
         do: CatalogPage.paginate(providers, args["page"], args["page_size"])
  end

  def call(actor, "list_provider_models", args, options) do
    with {:ok, %{models: models}} <-
           Calls.list_provider_models(
             actor,
             args["tenant_key"],
             args["provider"],
             args["capability"],
             options
           ),
         do: CatalogPage.paginate(models, args["page"], args["page_size"])
  end

  def error(_name, reason) when reason in [:call_spec_page_out_of_range, :page_out_of_range],
    do: %{code: "page_out_of_range"}

  def error(name, reason) when name in ["list_providers", "list_provider_models"] do
    {_status, projected} = ProviderCatalogErrors.response(reason)
    projected
  end

  def error(_name, reason) do
    {_status, projected} = CallSpecErrors.response(reason)
    projected
  end

  defp action(name), do: if(name in @write_names, do: :write, else: :read)

  defp validate(name, arguments) when is_map(arguments) do
    with %{inputSchema: schema} <- Enum.find(@tools, &(&1.name == name)),
         {:ok, validated} <- ExMCP.Server.Tools.Helpers.validate_arguments(arguments, schema) do
      {:ok, validated}
    else
      _invalid -> {:error, :invalid_tool_arguments}
    end
  end

  defp validate(_name, _arguments), do: {:error, :invalid_tool_arguments}
end
