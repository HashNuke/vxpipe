defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.ResponseOrigins do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Speech.Session

  @maximum_contexts 16

  def new, do: %{current: nil, accepted: %{}}

  def accepted_fingerprint(state, context) when is_reference(context),
    do: Map.fetch(state.response_origins.accepted, context)

  def accepted_fingerprint(_state, _context), do: :error

  def current?(state, fingerprint) do
    case fingerprint(state) do
      {:ok, ^fingerprint} -> true
      _other -> false
    end
  end

  def submit(state, operation) do
    case prepare(state) do
      {:ok, context, fingerprint} ->
        result = dispatch(state.session, operation, options(context))
        {result, if(accepted?(result), do: accept(state, context, fingerprint), else: state)}

      {:error, _reason} = error ->
        {error, state}
    end
  end

  defp prepare(%{descriptor: %{response_start?: true}} = state) do
    origin = state.response_origins

    with {:ok, fingerprint} <- fingerprint(state) do
      candidate(origin, fingerprint)
    end
  end

  defp prepare(_state), do: {:ok, nil, nil}

  defp fingerprint(state) do
    epoch = state.input_epoch || direct_epoch(state)

    cond do
      state.held? or not is_reference(epoch) ->
        {:error, :held}

      not present?(state, state.human_id) or not present?(state, state.agent_id) ->
        {:error, :policy_denied}

      not Output.audio_route_permitted?(state, state.human_id, state.agent_id) or
          not Output.audio_route_permitted?(state, state.agent_id, state.human_id) ->
        {:error, :policy_denied}

      true ->
        {:ok,
         %{
           allocation: state.session.generation,
           source: {state.caller_source, state.human_id, state.frame_identity},
           epoch: epoch,
           lifecycle_revision: state.origin_lifecycle_revision,
           direct_policy_revision: state.origin_policy_revision,
           input_interval: interval(state, :audio_input, state.human_id),
           output_interval: interval(state, :audio_output, state.human_id),
           agent_input_interval: interval(state, :audio_input, state.agent_id)
         }}
    end
  end

  defp candidate(%{current: context, accepted: accepted}, fingerprint)
       when is_reference(context) do
    if Map.get(accepted, context) == fingerprint,
      do: {:ok, context, fingerprint},
      else: new_candidate(accepted, fingerprint)
  end

  defp candidate(%{accepted: accepted}, fingerprint), do: new_candidate(accepted, fingerprint)

  defp new_candidate(accepted, fingerprint) do
    if map_size(accepted) < @maximum_contexts,
      do: {:ok, make_ref(), fingerprint},
      else: {:error, :busy}
  end

  defp accept(state, nil, _fingerprint), do: state

  defp accept(state, context, fingerprint) do
    origins = state.response_origins

    %{
      state
      | response_origins: %{
          origins
          | current: context,
            accepted: Map.put_new(origins.accepted, context, fingerprint)
        }
    }
  end

  defp accepted?(:ok), do: true
  defp accepted?({:ok, _handle}), do: true
  defp accepted?(_result), do: false

  defp options(nil), do: []
  defp options(context), do: [response_context: context]

  defp dispatch(session, {:audio, pcm}, options), do: Session.push_audio(session, pcm, options)
  defp dispatch(session, {:text, text}, options), do: Session.push_text(session, text, options)

  defp dispatch(session, {:activity, boundary}, options),
    do: Session.input_activity(session, boundary, options)

  defp direct_epoch(%{input_required?: false, session: session}), do: session.generation
  defp direct_epoch(_state), do: nil

  defp present?(%{input_policy: nil}, _participant), do: true

  defp present?(%{input_policy: %Snapshot{} = policy}, participant),
    do: MapSet.member?(policy.present_participant_ids, participant)

  defp interval(%{input_policy: nil, policy_revision: revision}, _scope, _participant),
    do: revision

  defp interval(state, scope, participant),
    do: Snapshot.interval(state.input_policy, scope, participant)
end
