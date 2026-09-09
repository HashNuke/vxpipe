defmodule Vxpipe.Console.SampleCall do
  @moduledoc false

  use GenServer

  alias Vxpipe.Console.{SampleCallBackend, SampleCallState}

  @call_timeout_ms 5_000

  def start_link(options) do
    options =
      Keyword.validate!(options,
        backend: {SampleCallBackend, []},
        definition: nil,
        initial_variables: %{},
        name: __MODULE__,
        tenant_name: "Vxpipe development sample"
      )

    GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  end

  def prepare(server \\ __MODULE__) do
    case GenServer.whereis(server) do
      nil ->
        {:error, :disabled}

      process ->
        try do
          GenServer.call(process, :prepare, @call_timeout_ms)
        catch
          :exit, _reason -> {:error, :unavailable}
        end
    end
  end

  @impl true
  def init(options) do
    definition = Keyword.fetch!(options, :definition)
    initial_variables = Keyword.fetch!(options, :initial_variables)
    tenant_name = Keyword.fetch!(options, :tenant_name)

    unless is_map(definition) and is_map(initial_variables) and is_binary(tenant_name) and
             byte_size(String.trim(tenant_name)) > 0 do
      raise ArgumentError, "invalid trusted sample-call configuration"
    end

    state = %SampleCallState{
      backend: Keyword.fetch!(options, :backend),
      definition: definition,
      initial_variables: initial_variables,
      tenant_name: tenant_name,
      status: :provisioning,
      api_key: nil,
      participant_key: nil,
      tenant_key: nil
    }

    {:ok, state, {:continue, :provision}}
  end

  @impl true
  def handle_continue(:provision, state), do: {:noreply, provision(state)}

  @impl true
  def handle_call(:prepare, _from, %SampleCallState{status: :ready} = state) do
    {:reply, prepare_call(state), state}
  end

  def handle_call(:prepare, _from, state) do
    state = provision(state)

    case state.status do
      :ready -> {:reply, prepare_call(state), state}
      {:failed, _reason} -> {:reply, {:error, :unavailable}, state}
    end
  end

  defp provision(%SampleCallState{} = state) do
    with {:ok, tenant, api_key} <- backend(state, :bootstrap, [state.tenant_name]),
         {:ok, draft} <- backend(state, :save_definition, [tenant.key, state.definition]),
         {:ok, published} <-
           backend(state, :publish_definition, [tenant.key, draft.definition_id, draft.revision]),
         {:ok, participant_key} <- entry_caller_route(published) do
      %SampleCallState{
        state
        | status: :ready,
          tenant_key: tenant.key,
          participant_key: participant_key,
          api_key: api_key
      }
    else
      {:error, reason} -> %{state | status: {:failed, reason}}
    end
  end

  defp prepare_call(state) do
    with {:ok, principal} <-
           backend(state, :authenticate, [state.tenant_key, state.api_key.secret]),
         {:ok, _call, token} <-
           backend(state, :prepare_call, [
             principal,
             state.participant_key,
             state.initial_variables
           ]) do
      {:ok, token}
    else
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp entry_caller_route(published) do
    entry_caller = published.compiled_metadata["entry_caller"]

    case Enum.find(published.routes, &(&1.participant_ref == entry_caller)) do
      nil -> {:error, :entry_caller_route_not_found}
      route -> {:ok, route.key}
    end
  end

  defp backend(state, function, arguments) do
    {module, context} = state.backend

    try do
      apply(module, function, [context | arguments])
    rescue
      _exception -> {:error, :backend_unavailable}
    catch
      _kind, _reason -> {:error, :backend_unavailable}
    end
  end
end
