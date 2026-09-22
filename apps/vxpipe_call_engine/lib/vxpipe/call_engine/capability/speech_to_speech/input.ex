defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Input do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.ResponseOrigins

  def format(%{descriptor: %{input_format: format}}) do
    {:ok, %{codec: format.encoding, sample_rate: format.sample_rate, channels: format.channels}}
  end

  def format(_state), do: {:error, :not_ready}

  def transcript_interval(%{input_policy: nil} = state, _source), do: state.policy_revision

  def transcript_interval(state, source),
    do: Snapshot.interval(state.input_policy, :speech_to_text, source)

  def audio_interval(%{input_policy: nil} = state, _source), do: state.policy_revision

  def audio_interval(state, source),
    do: Snapshot.interval(state.input_policy, :audio_input, source)

  def bind(state, ingress, owner) when state.owner == owner and state.input == nil do
    {:reply, :ok, %{state | input: ingress, input_monitor: Process.monitor(ingress)}}
  end

  def bind(state, _ingress, _owner), do: {:reply, {:error, :wrong_owner}, state}

  def hold(%{input: nil} = state), do: %{state | held?: true, input_epoch: nil, caller_turns: %{}}

  def hold(state) do
    _ = STSIngress.hold(state.input)
    %{state | held?: true, input_epoch: nil, caller_turns: %{}}
  end

  def release(%{input: nil, input_required?: true}, _epoch), do: {:error, :not_ready}

  def release(%{input: nil} = state, epoch),
    do: {:ok, %{state | held?: false, input_epoch: epoch}}

  def release(state, epoch) do
    with {:ok, contract} <- STSIngress.input_contract(state.input),
         :ok <- STSIngress.open(state.input, epoch),
         do: {:ok, %{state | held?: false, input_epoch: epoch, input_contract: contract}}
  end

  def apply_policy(state, snapshot) do
    with {:ok, snapshot} <- Snapshot.prepare(snapshot, state.input_policy),
         do:
           {:ok,
            %{
              state
              | input_policy: snapshot,
                policy: snapshot.effective,
                policy_revision: snapshot.revision
            }}
  end

  def deliver(state, ingress, reference, frame, revision, epoch) do
    {result, state} =
      case validate(state, ingress, frame, revision, epoch) do
        :ok -> ResponseOrigins.submit(state, {:audio, frame.payload})
        error -> {error, state}
      end

    if ingress == state.input,
      do: send(ingress, {:vxpipe_sts_input_result, self(), reference, result})

    {:noreply,
     if(result == :ok,
       do: %{state | input_sequence: frame.sequence_number},
       else: %{state | dropped_ingress_chunks: state.dropped_ingress_chunks + 1}
     )}
  end

  defp validate(state, ingress, %AudioFrame{} = frame, revision, epoch) do
    now = System.monotonic_time(:millisecond)

    cond do
      ingress != state.input or state.input == nil ->
        {:error, :wrong_connection}

      state.held? or epoch == nil or epoch != state.input_epoch ->
        {:error, :held}

      revision != state.policy_revision ->
        {:error, :stale_policy}

      Map.take(frame, Map.keys(state.frame_identity)) != state.frame_identity ->
        {:error, :wrong_connection}

      frame.participant_id != state.human_id ->
        {:error, :wrong_connection}

      not valid_audio?(frame, state.input_contract) ->
        {:error, :unsupported_audio}

      not is_integer(frame.sequence_number) or frame.sequence_number < 0 or
          (state.input_sequence != nil and frame.sequence_number <= state.input_sequence) ->
        {:error, :stale_sequence}

      not is_integer(frame.received_at) or frame.received_at > now or
          now - frame.received_at > state.input_contract.maximum_age_ms ->
        {:error, :stale_frame}

      not Output.audio_route_permitted?(state, state.human_id, state.agent_id) ->
        {:error, :policy_denied}

      true ->
        :ok
    end
  end

  defp validate(_state, _ingress, _frame, _revision, _epoch), do: {:error, :unsupported_audio}

  defp valid_audio?(frame, %{track: track}) do
    frame.track_id == track.track_id and frame.codec == track.codec and
      frame.sample_rate == track.sample_rate and frame.channels == track.channels and
      is_binary(frame.payload) and byte_size(frame.payload) > 0 and
      rem(byte_size(frame.payload), 2) == 0
  end

  defp valid_audio?(_frame, _contract), do: false
end
