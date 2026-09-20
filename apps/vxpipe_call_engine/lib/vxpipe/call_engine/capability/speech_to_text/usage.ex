defmodule Vxpipe.CallEngine.Capability.SpeechToText.Usage do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToText.State
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Usage.{ProviderContext, SpeechToTextSession}

  @spec start_session(State.t()) :: State.t()
  def start_session(%State{usage: nil} = state) do
    if active?(state), do: start_active_session(state), else: state
  end

  def start_session(%State{} = state), do: state

  defp start_active_session(%State{} = state) do
    with context when is_list(context) <- state.usage_context,
         call_id when is_binary(call_id) <- Keyword.get(context, :call_id),
         participant_id when participant_id == state.identity.participant_id <-
           Keyword.get(context, :participant_id),
         activation_id when is_binary(activation_id) or is_nil(activation_id) <-
           Keyword.get(context, :activation_id),
         %ProviderContext{} = provider <- Keyword.get(context, :provider) do
      session =
        SpeechToTextSession.start(
          state.identity,
          Id.generate(:stt_attempt),
          Id.generate(:speech_service_interval),
          call_id,
          activation_id,
          provider
        )

      %{state | usage: session}
    else
      _not_configured -> state
    end
  end

  @spec transition(State.t(), State.t()) :: State.t()
  def transition(%State{} = previous, %State{} = updated) do
    if same_session?(previous, updated) do
      updated
    else
      updated
      |> finish_session(:cancelled)
      |> start_session()
    end
  end

  @spec accept_input(State.t()) :: State.t()
  def accept_input(%State{usage: %SpeechToTextSession{} = session} = state) do
    {session, observations} =
      SpeechToTextSession.accept_input(session, DateTime.utc_now(:millisecond))

    send_observations(state.owner, observations)
    %{state | usage: session}
  end

  def accept_input(%State{} = state), do: state

  @spec observe_signal(State.t(), Signal.t()) :: State.t()
  def observe_signal(%State{usage: %SpeechToTextSession{} = session} = state, %Signal{} = signal) do
    {session, observations} =
      SpeechToTextSession.observe_signal(
        session,
        signal,
        retain_text_measurement?(state.policy),
        DateTime.utc_now(:millisecond)
      )

    send_observations(state.owner, observations)
    %{state | usage: session}
  end

  def observe_signal(%State{} = state, %Signal{}), do: state

  @spec finish_session(State.t(), :succeeded | :failed | :cancelled) :: State.t()
  def finish_session(%State{usage: %SpeechToTextSession{} = session} = state, outcome)
      when outcome in [:succeeded, :failed, :cancelled] do
    {_session, observations} =
      SpeechToTextSession.finish(session, outcome, DateTime.utc_now(:millisecond))

    send_observations(state.owner, observations)
    %{state | usage: nil}
  end

  def finish_session(%State{} = state, outcome)
      when outcome in [:succeeded, :failed, :cancelled],
      do: state

  defp retain_text_measurement?(%Snapshot{effective: %Effective{save_transcripts: true}}),
    do: true

  defp retain_text_measurement?(_policy), do: false

  defp send_observations(_owner, []), do: :ok

  defp send_observations(owner, observations) when is_pid(owner) do
    send(owner, {:vxpipe_usage_observations, self(), observations})
    :ok
  end

  defp active?(%State{session: session, readiness_status: :ready}),
    do: not is_nil(session)

  defp active?(%State{}), do: false

  defp same_session?(%State{session: session}, %State{session: session}),
    do: true

  defp same_session?(%State{}, %State{}), do: false
end
