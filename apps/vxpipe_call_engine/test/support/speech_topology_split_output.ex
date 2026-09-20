defmodule Vxpipe.CallEngine.SpeechTopologySplitOutput do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.SpeechTopologyAudio

  @credit_timeout 1_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: options[:name])

  @impl true
  def init(options) do
    {:ok,
     %{
       channel: Keyword.fetch!(options, :channel),
       provider: Keyword.fetch!(options, :provider),
       consumer: Keyword.fetch!(options, :consumer),
       format: nil,
       current: nil,
       session_played_ms: 0
     }}
  end

  @impl true
  def handle_call({:control, deadline, operation}, {caller, _tag}, state) do
    if caller == GenServer.whereis(state.channel) and live?(deadline) do
      control(operation, state)
    else
      {:reply, {:error, :closed}, state}
    end
  end

  def handle_call({:submit_audio, request, payload}, {caller, _tag}, state) do
    if caller == GenServer.whereis(state.provider) and open?(state, request) and
         state.current.submitted? and is_nil(state.current.awaiting) do
      audio = %SpeechTopologyAudio{ref: make_ref(), request_ref: request, payload: payload}
      timer = Process.send_after(self(), {:credit_expired, audio.ref}, @credit_timeout)
      awaiting = %{audio: audio, timer: timer}

      current = %{
        state.current
        | awaiting: awaiting,
          generated_bytes: state.current.generated_bytes + byte_size(payload)
      }

      GenServer.cast(state.channel, {:output_audio, self(), audio})
      {:reply, {:ok, audio.ref}, %{state | current: current}}
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call(
        {:consumer, deadline, {:validate_audio, audio}},
        {caller, _tag},
        %{consumer: caller} = state
      ) do
    if live?(deadline),
      do: validate(audio, state),
      else: {:reply, {:error, :command_timeout}, state}
  end

  def handle_call(
        {:consumer, deadline, {:ack_audio, audio}},
        {caller, _tag},
        %{consumer: caller} = state
      ) do
    if live?(deadline),
      do: acknowledge(audio, state),
      else: {:reply, {:error, :command_timeout}, state}
  end

  def handle_call({:consumer, _deadline, _operation}, _from, state),
    do: {:reply, {:error, :not_owner}, state}

  @impl true
  def handle_info(
        {:credit_expired, reference},
        %{current: %{awaiting: %{audio: %{ref: reference}}}} = state
      ),
      do: {:stop, :normal, state}

  def handle_info({:credit_expired, _stale}, state), do: {:noreply, state}

  defp control({:configure, format}, state),
    do: {:reply, :ok, %{state | format: format}}

  defp control({:begin, request}, %{current: nil} = state) do
    current = %{
      request: request,
      phase: :open,
      submitted?: false,
      awaiting: nil,
      generated_bytes: 0,
      accepted_bytes: 0,
      uncredited_bytes: 0,
      played_ms: 0
    }

    {:reply, :ok, %{state | current: current}}
  end

  defp control({:submitted, request}, state) do
    if open?(state, request) and not state.current.submitted? do
      {:reply, :ok, %{state | current: %{state.current | submitted?: true}}}
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  defp control({:completed, request}, state) do
    if open?(state, request) and is_nil(state.current.awaiting) do
      {:reply, :ok, %{state | current: %{state.current | phase: :completed}}}
    else
      {:reply, {:error, :output_pending}, state}
    end
  end

  defp control({:fence, request}, state) do
    case state.current do
      %{request: ^request, phase: phase} = current when phase in [:open, :completed] ->
        cancel_credit(current.awaiting)
        uncredited = if current.awaiting, do: byte_size(current.awaiting.audio.payload), else: 0

        {:reply, :ok,
         %{
           state
           | current: %{current | phase: :fenced, awaiting: nil, uncredited_bytes: uncredited}
         }}

      _other ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  defp control({:played, request, played_ms}, state) do
    case state.current do
      %{request: ^request, phase: :fenced} = current
      when is_integer(played_ms) and played_ms >= current.played_ms ->
        maximum =
          div(
            (current.accepted_bytes + current.uncredited_bytes) * 1_000,
            state.format.sample_rate * 2
          )

        if played_ms <= maximum do
          total = state.session_played_ms + played_ms - current.played_ms
          report = %{request_ref: request, played_ms: played_ms, session_played_ms: total}
          current = %{current | played_ms: played_ms}
          {:reply, {:ok, report}, %{state | current: current, session_played_ms: total}}
        else
          {:reply, {:error, :invalid_playback}, state}
        end

      _other ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  defp control({:cancelled, request}, state) do
    case state.current do
      %{request: ^request, phase: :fenced} = current ->
        {:reply, :ok, %{state | current: %{current | phase: :cancelled}}}

      _other ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  defp control({:settle, request}, state) do
    case state.current do
      %{request: ^request, phase: phase} when phase in [:fenced, :cancelled] ->
        {:reply, :ok, %{state | current: nil}}

      _other ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  defp control(_operation, state), do: {:reply, {:error, :stale_request}, state}

  defp acknowledge(audio, state) do
    case state.current do
      %{request: request, phase: :open, awaiting: %{audio: ^audio, timer: timer}} ->
        Process.cancel_timer(timer)

        send(
          GenServer.whereis(state.provider),
          {:topology_credit, self(), request, audio.ref, :ok}
        )

        current = %{
          state.current
          | awaiting: nil,
            accepted_bytes: state.current.accepted_bytes + byte_size(audio.payload)
        }

        {:reply, :ok, %{state | current: current}}

      _other ->
        {:reply, {:error, :stale_audio}, state}
    end
  end

  defp validate(audio, state) do
    case state.current do
      %{phase: :open, awaiting: %{audio: ^audio}} -> {:reply, :ok, state}
      _other -> {:reply, {:error, :stale_audio}, state}
    end
  end

  defp cancel_credit(nil), do: :ok
  defp cancel_credit(%{timer: timer}), do: Process.cancel_timer(timer)

  defp open?(%{current: %{request: request, phase: :open}}, request), do: true
  defp open?(_state, _request), do: false

  defp live?(deadline), do: deadline > System.monotonic_time(:millisecond)
end
