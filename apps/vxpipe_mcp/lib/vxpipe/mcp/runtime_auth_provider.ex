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
  @enforce_keys [:tenant, :connection_id, :generation, :auth_method, :resolver]
  defstruct @enforce_keys

  @impl true
  def init(%__MODULE__{} = config), do: init(Map.from_struct(config))

  def init(
        %{
          tenant: tenant,
          connection_id: id,
          generation: generation,
          auth_method: method,
          resolver: {module, _context}
        } = config
      )
      when is_binary(tenant) and byte_size(tenant) in 1..128 and is_binary(id) and
             byte_size(id) in 1..128 and is_integer(generation) and generation > 0 and
             method in ~w(none bearer headers basic oauth) and is_atom(module) do
    if Map.keys(config) -- @enforce_keys == [] and Code.ensure_loaded?(module) and
         function_exported?(module, :resolve, 4),
       do: {:ok, struct!(__MODULE__, config)},
       else: unavailable()
  end

  def init(_), do: unavailable()

  @impl true
  def get_token(%__MODULE__{auth_method: method} = state) do
    case resolve(state) do
      {:ok, %{auth_method: "oauth", token: token}} when method == "oauth" ->
        case Vxpipe.MCP.Authentication.headers(type: :bearer, token: token) do
          {:ok, _} -> {:ok, token, state}
          _ -> unavailable()
        end

      {:ok, %{auth_method: ^method}} when method != "oauth" ->
        {:ok, nil, state}

      _ ->
        unavailable()
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
    module.resolve(context, state.tenant, state.connection_id, state.generation)
  rescue
    _ -> :unavailable
  catch
    _, _ -> :unavailable
  end

  defp unavailable, do: exit(:mcp_credentials_unavailable)
end
