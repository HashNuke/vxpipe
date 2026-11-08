defmodule Vxpipe.MCP.RuntimeAuthProvider do
  @moduledoc """
  Resolves pinned runtime credentials at ExMCP provider-controlled submission points.

  ExMCP retains old credentials on provider error tuples. This adapter therefore
  exits with a fixed rejection signal before HTTP work begins. The pinned transport
  patch converts that signal into a submission error; SSE terminates with redacted
  status rather than entering its connection retry loop.
  Challenge callbacks never authorize a retry or start browser authentication.
  """
  @behaviour ExMCP.Authorization.Provider
  @derive {Inspect, only: []}
  @enforce_keys [:tenant, :connection_id, :generation, :auth_method, :endpoint, :resolver]
  defstruct @enforce_keys ++ [session: nil]

  @impl true
  def init(%__MODULE__{} = config), do: init(Map.from_struct(config))

  def init(
        %{
          tenant: tenant,
          connection_id: id,
          generation: generation,
          auth_method: method,
          endpoint: endpoint,
          resolver: {module, _context}
        } = config
      )
      when is_binary(tenant) and byte_size(tenant) in 1..128 and is_binary(id) and
             byte_size(id) in 1..128 and is_integer(generation) and generation > 0 and
             method in ~w(none bearer headers basic oauth) and is_binary(endpoint) and
             is_atom(module) do
    if Map.keys(config) -- (@enforce_keys ++ [:session]) == [] and
         (is_nil(Map.get(config, :session)) or is_pid(Map.get(config, :session))) and
         Code.ensure_loaded?(module) and
         function_exported?(module, :resolve, 4),
       do: {:ok, struct!(__MODULE__, config)},
       else: unavailable()
  end

  def init(_), do: unavailable()

  @doc false
  def with_session(options, integration) when is_pid(integration) do
    case Keyword.fetch(options, :auth_provider) do
      {:ok, {__MODULE__, state}} ->
        Keyword.put(options, :auth_provider, {__MODULE__, %{state | session: integration}})

      :error ->
        options
    end
  end

  @impl true
  def get_token(%__MODULE__{auth_method: method, endpoint: endpoint} = state) do
    case resolve(state) do
      {:ok, %{auth_method: "oauth", endpoint: ^endpoint, token: token}} when method == "oauth" ->
        case Vxpipe.MCP.Authentication.headers(type: :bearer, token: token) do
          {:ok, _} -> {:ok, token, state}
          _ -> unavailable()
        end

      {:ok, %{auth_method: ^method, endpoint: ^endpoint}} when method != "oauth" ->
        {:ok, nil, state}

      _ ->
        unavailable()
    end
  end

  @doc "Resolves and validates the complete credential header set for one submission."
  def get_headers(%__MODULE__{} = state), do: headers(state, resolve(state))

  @doc "Obtains cleanup headers only from a resolver with a non-renewing capability."
  def get_cleanup_headers(%__MODULE__{} = state), do: headers(state, resolve_cleanup(state))

  defp headers(%__MODULE__{auth_method: method, endpoint: endpoint} = state, resolved) do
    with {:ok, %{auth_method: ^method, endpoint: ^endpoint} = current} <- resolved,
         {:ok, headers} <- request_headers(current),
         {:ok, validated} <- validate_headers(headers) do
      {:ok, validated, state}
    else
      _ -> unavailable()
    end
  end

  defp request_headers(%{auth_method: "oauth", token: token} = current) do
    with {:ok, bearer} <- Vxpipe.MCP.Authentication.headers(type: :bearer, token: token),
         headers <- Map.get(current, :headers, bearer),
         {:ok, validated} <- validate_headers(headers),
         true <- List.keyfind(validated, "authorization", 0) == hd(bearer) do
      {:ok, validated}
    else
      _ -> {:error, :invalid_authentication}
    end
  end

  defp request_headers(%{auth_method: "none", headers: []}), do: {:ok, []}

  defp request_headers(%{auth_method: method, headers: [_ | _] = headers})
       when method in ~w(bearer basic headers) do
    with {:ok, normalized} <- validate_headers(headers),
         true <- method_headers?(method, normalized) do
      {:ok, normalized}
    else
      _ -> {:error, :invalid_authentication}
    end
  end

  defp request_headers(_), do: {:error, :invalid_authentication}
  defp validate_headers([]), do: {:ok, []}

  defp validate_headers(headers),
    do: Vxpipe.MCP.Authentication.headers(type: :custom_headers, headers: headers)

  defp method_headers?("headers", _headers), do: true

  defp method_headers?(method, headers) do
    case {method, List.keyfind(headers, "authorization", 0)} do
      {"bearer", {_, "Bearer " <> token}} ->
        match?({:ok, _}, Vxpipe.MCP.Authentication.headers(type: :bearer, token: token))

      {"basic", {_, "Basic " <> encoded}} ->
        valid_basic?(encoded)

      _ ->
        false
    end
  end

  defp valid_basic?(encoded) do
    with {:ok, decoded} <- Base.decode64(encoded),
         [username, password] <- :binary.split(decoded, ":"),
         true <- byte_size(username) in 1..1024 and byte_size(password) in 1..4096 do
      Enum.all?(:binary.bin_to_list(decoded), &(&1 in 32..126))
    else
      _ -> false
    end
  end

  @impl true
  def handle_unauthorized(_challenge, _scopes, state),
    do: {:error, :mcp_authorization_required, state}

  @impl true
  def handle_forbidden(_challenge, _scopes, state),
    do: {:error, :mcp_authorization_required, state}

  defp resolve(state) do
    {module, context} = state.resolver

    if state.session do
      module.resolve(context, state.tenant, state.connection_id, state.generation, state.session)
    else
      module.resolve(context, state.tenant, state.connection_id, state.generation)
    end
  rescue
    _ -> :unavailable
  catch
    _, _ -> :unavailable
  end

  defp unavailable, do: exit(:mcp_credentials_unavailable)

  defp resolve_cleanup(state) do
    {module, context} = state.resolver

    if function_exported?(module, :resolve_cleanup, 4),
      do: module.resolve_cleanup(context, state.tenant, state.connection_id, state.generation),
      else: :unavailable
  rescue
    _ -> :unavailable
  catch
    _, _ -> :unavailable
  end
end
