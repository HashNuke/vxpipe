defmodule Vxpipe.CallEngine.SpeechTopologyProvider do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Provider.MorseCode.Encoder

  @chunk_samples 160

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: options[:name])

  @impl true
  def init(options) do
    {:ok,
     %{
       channel: Keyword.fetch!(options, :channel),
       input: Keyword.fetch!(options, :input),
       target: Keyword.fetch!(options, :target),
       config: Keyword.fetch!(options, :config),
       current: nil
     }}
  end

  @impl true
  def handle_call({:speak, request, text}, {caller, _tag}, state) do
    if caller == GenServer.whereis(state.input) do
      case state.current do
        current when is_nil(current) or current.terminal? ->
          start_speech(request, text, state)

        _current ->
          {:reply, {:error, :busy}, state}
      end
    else
      {:reply, {:error, :not_owner}, state}
    end
  end

  def handle_call({:cancel, request, _played_ms}, {caller, _tag}, state) do
    if caller == GenServer.whereis(state.input),
      do: cancel(request, state),
      else: {:reply, {:error, :not_owner}, state}
  end

  def handle_call(_message, _from, state), do: {:reply, {:error, :not_owner}, state}

  @impl true
  def handle_info(
        {:emit, request},
        %{current: %{request: request, encoder: encoder, awaiting: nil, terminal?: false}} = state
      ) do
    case Encoder.next(encoder, @chunk_samples) do
      {:ok, payload, encoder} ->
        case GenServer.call(state.target, {:submit_audio, request, payload}) do
          {:ok, credit} ->
            current = %{state.current | encoder: encoder, awaiting: credit}
            {:noreply, %{state | current: current}}

          {:error, :stale_request} ->
            {:noreply, %{state | current: %{state.current | terminal?: true}}}
        end

      :done ->
        case provider_event(state, request, :completed, nil) do
          :ok ->
            {:noreply, %{state | current: %{state.current | encoder: nil, terminal?: true}}}

          {:error, :cancelled} ->
            {:noreply, %{state | current: %{state.current | encoder: nil, terminal?: true}}}
        end
    end
  end

  def handle_info(
        {:topology_credit, target, request, credit, :ok},
        %{current: %{request: request, awaiting: credit, terminal?: false} = current} = state
      ) do
    if target == GenServer.whereis(state.target) do
      send(self(), {:emit, request})
      {:noreply, %{state | current: %{current | awaiting: nil}}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_stale, state), do: {:noreply, state}

  defp start_speech(request, text, state) do
    provider_request_id =
      "isolated-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))

    with {:ok, encoder} <- Encoder.start(state.config, text),
         :ok <- provider_event(state, request, :input_submitted, provider_request_id) do
      send(self(), {:emit, request})

      current = %{
        request: request,
        provider_request_id: provider_request_id,
        encoder: encoder,
        awaiting: nil,
        terminal?: false
      }

      {:reply, :ok, %{state | current: current}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp cancel(request, %{current: %{request: request, terminal?: false} = current} = state) do
    case provider_event(state, request, :cancelled, current.provider_request_id) do
      :ok ->
        current = %{current | encoder: nil, awaiting: nil, terminal?: true}
        {:reply, :ok, %{state | current: current}}

      error ->
        {:reply, error, state}
    end
  end

  defp cancel(request, %{current: %{request: request, terminal?: true}} = state),
    do: {:reply, :ok, state}

  defp cancel(_request, state), do: {:reply, {:error, :stale_request}, state}

  defp provider_event(state, request, kind, provider_request_id) do
    GenServer.call(
      state.channel,
      {:provider_event, request, kind, provider_request_id},
      1_000
    )
  end
end
