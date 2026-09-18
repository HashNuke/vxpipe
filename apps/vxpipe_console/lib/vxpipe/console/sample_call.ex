defmodule Vxpipe.Console.SampleCall do
  @moduledoc false

  use GenServer

  alias Vxpipe.Console.{SampleCallBackend, SampleCallState}

  @call_timeout_ms 5_000

  def start_link(options) do
    options =
      Keyword.validate!(options,
        backend: {SampleCallBackend, []},
        call_spec: nil,
        initial_variables: %{},
        name: __MODULE__,
        tenant_key: nil,
        transfer_participant: nil
      )

    GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  end

  def prepare(server \\ __MODULE__) do
    safe_call(server, :prepare)
  end

  def prepare_transfer(server \\ __MODULE__), do: safe_call(server, :prepare_transfer)

  @impl true
  def init(options) do
    call_spec = Keyword.fetch!(options, :call_spec)
    initial_variables = Keyword.fetch!(options, :initial_variables)
    tenant_key = Keyword.fetch!(options, :tenant_key)
    transfer_participant = Keyword.fetch!(options, :transfer_participant)

    unless is_map(call_spec) and is_map(initial_variables) and is_binary(tenant_key) and
             byte_size(String.trim(tenant_key)) > 0 and
             valid_transfer_participant?(transfer_participant) do
      raise ArgumentError, "invalid trusted sample-call configuration"
    end

    state = %SampleCallState{
      backend: Keyword.fetch!(options, :backend),
      call_spec: call_spec,
      initial_variables: initial_variables,
      tenant_key: tenant_key,
      transfer_participant: transfer_participant,
      status: :provisioning,
      api_key: nil,
      call_id: nil,
      participant_key: nil,
      transfer_participant_key: nil
    }

    {:ok, state, {:continue, :provision}}
  end

  @impl true
  def handle_continue(:provision, state), do: {:noreply, provision(state)}

  @impl true
  def handle_call(:prepare, _from, %SampleCallState{status: :ready} = state) do
    prepare_reply(state)
  end

  def handle_call(:prepare, _from, state) do
    state = provision(state)

    case state.status do
      :ready -> prepare_reply(state)
      {:failed, _reason} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call(:prepare_transfer, _from, state) do
    state = provision(state)

    case state do
      %SampleCallState{status: {:failed, _reason}} ->
        {:reply, {:error, :unavailable}, state}

      %SampleCallState{transfer_participant_key: nil} ->
        {:reply, {:error, :disabled}, state}

      %SampleCallState{call_id: nil} ->
        {:reply, {:error, :call_not_prepared}, state}

      %SampleCallState{} ->
        {:reply, issue_transfer_token(state), state}
    end
  end

  defp provision(%SampleCallState{status: :ready} = state), do: state

  defp provision(%SampleCallState{} = state) do
    with {:ok, draft} <- backend(state, :save_call_spec, [state.tenant_key, state.call_spec]),
         {:ok, published} <-
           backend(state, :publish_call_spec, [
             state.tenant_key,
             draft.call_spec_id,
             draft.revision
           ]),
         {:ok, participant_key} <- entry_caller_route(published),
         {:ok, transfer_participant_key} <- transfer_participant_route(published, state),
         {:ok, api_key} <- backend(state, :issue_api_key, [state.tenant_key]) do
      %SampleCallState{
        state
        | status: :ready,
          participant_key: participant_key,
          transfer_participant_key: transfer_participant_key,
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

  defp prepare_reply(state) do
    case prepare_call(state) do
      {:ok, token} -> {:reply, {:ok, token}, %{state | call_id: token.call_id}}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  defp issue_transfer_token(state) do
    with {:ok, principal} <-
           backend(state, :authenticate, [state.tenant_key, state.api_key.secret]),
         {:ok, token} <-
           backend(state, :issue_join_token, [
             principal,
             state.call_id,
             state.transfer_participant_key
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

  defp transfer_participant_route(_published, %SampleCallState{transfer_participant: nil}),
    do: {:ok, nil}

  defp transfer_participant_route(published, state) do
    case Enum.find(published.routes, &(&1.participant_ref == state.transfer_participant)) do
      nil -> {:error, :transfer_participant_route_not_found}
      route -> {:ok, route.key}
    end
  end

  defp safe_call(server, message) do
    case GenServer.whereis(server) do
      nil ->
        {:error, :disabled}

      process ->
        try do
          GenServer.call(process, message, @call_timeout_ms)
        catch
          :exit, _reason -> {:error, :unavailable}
        end
    end
  end

  defp valid_transfer_participant?(nil), do: true

  defp valid_transfer_participant?(participant) when is_binary(participant),
    do: byte_size(String.trim(participant)) > 0

  defp valid_transfer_participant?(_invalid), do: false

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
