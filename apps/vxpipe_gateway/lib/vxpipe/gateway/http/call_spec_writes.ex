defmodule Vxpipe.Gateway.HTTP.CallSpecWrites do
  @moduledoc false
  import Plug.Conn
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.Calls.{CallSpecRevision, ProviderAuth}

  def init(options),
    do: %{
      enabled: Keyword.get(options, :enabled, false),
      backend: Keyword.get(options, :backend, {Vxpipe.Gateway.CallSpecAuthoring, []})
    }

  def route(conn, options, scope, tenant, segments) do
    case {conn.method, segments} do
      {"POST", []} ->
        handle(conn, options, scope, tenant, {:save, nil})

      {"PUT", [id]} ->
        handle(conn, options, scope, tenant, {:save, id})

      {"POST", [id, "revisions", version, "publish"]} ->
        handle(conn, options, scope, tenant, {:publish, id, version})

      _unmatched ->
        send_resp(conn, 404, "not found")
    end
  end

  def handle(conn, %{enabled: false}, _scope, _tenant, _operation),
    do: send_resp(conn, 404, "not found")

  def handle(conn, options, scope, tenant, operation) do
    with {:ok, secret} <- bearer(conn),
         {:ok, author} <- backend(options, :authenticate, [scope, tenant, secret]),
         :ok <- ProviderAuth.tenant_key(tenant),
         {:ok, function, arguments, status} <- input(operation, conn.body_params),
         {:ok, %CallSpecRevision{tenant_key: ^tenant} = revision} <-
           backend(options, function, [author, tenant | arguments]) do
      json(conn, status, %{call_spec: public_revision(revision)})
    else
      {:error, reason} -> error(conn, reason)
      _invalid_result -> error(conn, :authoring_unavailable)
    end
  end

  defp input({:save, id}, %{"source" => source} = body)
       when map_size(body) == 1 and is_map(source) do
    if is_nil(id) or valid_id?(id),
      do: {:ok, :save, [source, id], 201},
      else: {:error, :invalid_request}
  end

  defp input({:publish, id, version}, body) when is_map(body) and map_size(body) == 0 do
    with true <- valid_id?(id),
         {revision, ""} when revision > 0 and revision <= 2_147_483_647 <- Integer.parse(version) do
      {:ok, :publish, [id, revision], 200}
    else
      _invalid -> {:error, :invalid_request}
    end
  end

  defp input(_operation, _body), do: {:error, :invalid_request}

  defp valid_id?(id),
    do:
      is_binary(id) and byte_size(id) in 1..128 and String.valid?(id) and
        not String.contains?(id, [<<0>>, "\n", "\r"])

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> secret] when byte_size(secret) in 1..256 -> {:ok, secret}
      _invalid -> {:error, :invalid_api_key}
    end
  end

  defp backend(options, function, arguments) do
    {module, context} = options.backend
    apply(module, function, [context | arguments])
  rescue
    _error -> {:error, :authoring_unavailable}
  catch
    :exit, _reason -> {:error, :authoring_unavailable}
  end

  defp public_revision(revision) do
    %{
      call_spec_id: revision.call_spec_id,
      revision: revision.revision,
      schema_version: revision.schema_version,
      source_digest: revision.source_digest,
      published: not is_nil(revision.published_at),
      published_at: if(revision.published_at, do: DateTime.to_iso8601(revision.published_at)),
      validation_errors:
        if(revision.validation_errors == [], do: [], else: [%{code: "unsupported_call_plan"}]),
      routes:
        Enum.map(
          revision.routes,
          &%{
            participant_key: &1.key,
            participant_ref: &1.participant_ref,
            published: not is_nil(&1.published_at)
          }
        )
    }
  end

  defp error(conn, :invalid_api_key), do: failure(conn, 401, "invalid_api_key")

  defp error(conn, reason)
       when reason in [
              :insufficient_scope,
              :tenant_access_forbidden,
              :authoring_authority_required
            ],
       do: failure(conn, 403, "authoring_forbidden")

  defp error(conn, %Error{code: :provider_service_forbidden}),
    do: failure(conn, 403, "provider_service_forbidden")

  defp error(conn, %Error{code: :provider_credential_unavailable}),
    do: failure(conn, 422, "provider_credential_unavailable")

  defp error(conn, %Error{code: :telephony_caller_id_missing}),
    do: failure(conn, 422, "telephony_caller_id_missing")

  defp error(conn, %Error{}), do: failure(conn, 422, "invalid_call_spec")

  defp error(conn, reason)
       when reason in [:private_call_spec_material, :invalid_call_spec_source],
       do: failure(conn, 422, "invalid_call_spec")

  defp error(conn, reason) when reason in [:invalid_request, :invalid_tenant_key],
    do: failure(conn, 400, "invalid_request")

  defp error(conn, reason) when reason in [:not_found, :tenant_not_found],
    do: failure(conn, 404, "call_spec_not_found")

  defp error(conn, {:call_spec_not_publishable, _errors}),
    do: failure(conn, 409, "call_spec_not_publishable")

  defp error(conn, _reason), do: failure(conn, 503, "call_spec_authoring_unavailable")

  defp failure(conn, status, code), do: json(conn, status, %{error: %{code: code}})

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
