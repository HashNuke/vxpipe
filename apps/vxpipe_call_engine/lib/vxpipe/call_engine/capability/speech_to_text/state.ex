defmodule Vxpipe.CallEngine.Capability.SpeechToText.State do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Capability.SpeechToText.PrivateAllocation
  alias Vxpipe.CallEngine.MediaPolicy.{Snapshot, SpeechToTextDemand}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.Speech.{Descriptor, Event, Session}

  @maximum_audio_bytes 131_072

  @derive {Inspect, only: [:identity, :provider_module, :readiness_status, :policy_revision]}
  @enforce_keys [
    :descriptor,
    :identity,
    :last_provider_sequence,
    :media_format,
    :next_turn_index,
    :owner,
    :policy,
    :policy_revision,
    :provider_module,
    :provider_options,
    :provider_private,
    :scope,
    :session,
    :turn_indexes,
    :usage,
    :usage_context
  ]
  defstruct @enforce_keys ++
              [
                activity_agent_id: nil,
                readiness_generation: nil,
                readiness_status: :preparing,
                pending_policy: nil,
                private_allocation: nil,
                adopted_policy_token: nil
              ]

  @type t :: %__MODULE__{
          descriptor: Descriptor.t() | nil,
          activity_agent_id: String.t() | nil,
          identity: map(),
          last_provider_sequence: integer(),
          media_format: map(),
          next_turn_index: non_neg_integer(),
          owner: pid(),
          policy: Snapshot.t() | nil,
          policy_revision: non_neg_integer() | nil,
          private_allocation: PrivateAllocation.t() | nil,
          provider_module: module(),
          provider_options: term(),
          provider_private: keyword(),
          readiness_generation: reference(),
          readiness_status: :preparing | :ready | :failed,
          scope: Vxpipe.CallEngine.Speech.Scope.t() | nil,
          session: Vxpipe.CallEngine.Speech.Allocation.t() | nil,
          turn_indexes: %{optional(reference()) => non_neg_integer()},
          usage: nil | Vxpipe.CallEngine.Usage.SpeechToTextSession.t(),
          usage_context: nil | keyword()
        }

  @spec new(keyword()) ::
          {:ok, t()}
          | {:error, :invalid_initial_policy}
          | {:error, :invalid_preparation}
          | {:error, :provider_start_failed, module()}
  def new(options) do
    identity = %{
      tenant_id: Keyword.fetch!(options, :tenant_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
      connection_id: Keyword.fetch!(options, :connection_id)
    }

    owner = Keyword.fetch!(options, :owner)
    {provider_module, provider_options} = Keyword.fetch!(options, :provider)

    with {:ok, demanded?} <-
           initial_demand(
             options,
             identity.participant_id,
             Keyword.get(options, :activity_agent_id)
           ),
         {:ok, allocation} <- PrivateAllocation.new(options, identity.participant_id),
         {:ok, state} <-
           build_state(
             options,
             identity,
             owner,
             provider_module,
             provider_options,
             allocation,
             demanded?
           ) do
      {:ok, state}
    else
      {:error, reason} = error when reason in [:invalid_initial_policy, :invalid_preparation] ->
        error

      {:error, _reason} ->
        {:error, :provider_start_failed, provider_module}
    end
  end

  @spec send_audio(t(), AudioFrame.t()) ::
          :ok | {:error, :policy_denied | :unsupported_audio | :unavailable}
  def send_audio(%__MODULE__{} = state, %AudioFrame{} = frame) do
    cond do
      not supported_audio?(state, frame) ->
        {:error, :unsupported_audio}

      is_nil(state.session) ->
        {:error, :policy_denied}

      true ->
        case Session.push_audio(state.session, frame.payload) do
          :ok -> :ok
          {:error, reason} when reason in [:not_ready, :closed] -> {:error, :policy_denied}
          {:error, _reason} -> {:error, :unavailable}
        end
    end
  end

  @spec audio_delivery_current?(t(), map() | nil) :: boolean()
  def audio_delivery_current?(%__MODULE__{policy: nil, activity_agent_id: nil}, _intervals),
    do: true

  def audio_delivery_current?(
        %__MODULE__{policy: %Snapshot{} = policy} = state,
        %{speech_to_text: stt, input: input, output: output} = intervals
      )
      when is_integer(stt) and stt >= 0 and is_integer(input) and input >= 0 and
             is_integer(output) and output >= 0 and map_size(intervals) == 3 do
    source = state.identity.participant_id

    stt == Snapshot.interval(policy, :speech_to_text, source) and
      input == Snapshot.interval(policy, :audio_input, source) and
      output == Snapshot.interval(policy, :audio_output, source)
  end

  def audio_delivery_current?(%__MODULE__{}, _intervals), do: false

  @spec install_policy(t(), Snapshot.t()) ::
          {:ok, t()} | {:error, term(), t()}
  def install_policy(%__MODULE__{} = state, %Snapshot{} = snapshot) do
    case Snapshot.prepare(snapshot, state.policy) do
      {:ok, snapshot} -> apply_policy(state, snapshot)
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc false
  def input_binding(state) do
    {:ok, resource, status} = readiness(state)

    {:ok,
     %{
       identity: state.identity,
       media_format: Map.take(state.media_format, [:codec, :sample_rate, :channels]),
       resource: resource,
       status: status,
       policy_intervals: [state.policy_revision]
     }}
  end

  @doc false
  def prepare_session(%__MODULE__{} = state, snapshot, deadline) do
    prepared =
      %{
        state
        | usage: nil,
          pending_policy: nil,
          turn_indexes: %{},
          next_turn_index: 0
      }
      |> invalidate_readiness()
      |> put_policy(snapshot)

    start_prepared(prepared, deadline)
  end

  def prepared(%__MODULE__{session: session} = state, session, descriptor) do
    if descriptor == state.descriptor,
      do: {:ok, %{state | readiness_status: :ready}},
      else: {:error, :invalid_descriptor}
  end

  def prepared(%__MODULE__{}, _session, _descriptor), do: {:error, :stale_session}

  def event(
        %__MODULE__{session: session} = state,
        %Event{session: session} = event
      ) do
    with :ok <- Session.ack(session, event),
         {:ok, signal, state} <- semantic_signal(state, event) do
      {:ok, signal, state}
    else
      _invalid -> {:error, :invalid_provider_event}
    end
  end

  def event(%__MODULE__{}, %Event{}), do: {:error, :stale_session}

  def adopt_prepared(%__MODULE__{session: session} = state, deadline) do
    case Session.adopt(session, self(), deadline) do
      :ok -> {:ok, state}
      {:error, _reason} -> {:error, :policy_not_ready}
    end
  end

  @doc false
  def retire_active(%__MODULE__{session: session} = state, deadline)
      when not is_nil(session) do
    case Session.retire(session, deadline) do
      :ok ->
        retired = %{state | session: nil, turn_indexes: %{}, next_turn_index: 0}
        {:ok, invalidate_readiness(retired)}

      {:error, _reason} = error ->
        error
    end
  end

  def retire_active(%__MODULE__{} = state, _deadline), do: {:ok, state}

  @spec close(t()) :: t()
  def close(%__MODULE__{session: session} = state) when not is_nil(session) do
    _ = Session.close(session)

    %{state | session: nil, turn_indexes: %{}, next_turn_index: 0}
    |> invalidate_readiness()
  end

  def close(%__MODULE__{} = state), do: state

  @spec readiness(t()) :: {:ok, Resource.t(), :preparing | :ready | :failed}
  def readiness(%__MODULE__{} = state) do
    resource = %Resource{
      kind: :speech_to_text,
      scope: {:participant, state.identity.participant_id},
      binding: state.identity.connection_id,
      instance: self(),
      generation: state.readiness_generation,
      configuration:
        Resource.signature({
          state.provider_module,
          state.media_format,
          state.descriptor.settings
        }),
      policy_interval: state.policy_revision,
      adapter: Vxpipe.CallEngine.Capability.SpeechToText
    }

    status =
      if state.readiness_status == :ready and is_nil(state.session),
        do: :preparing,
        else: state.readiness_status

    {:ok, resource, status}
  end

  defp invalidate_readiness(state) do
    %{
      state
      | readiness_generation: make_ref(),
        adopted_policy_token: nil,
        readiness_status: initial_status(state)
    }
  end

  defp apply_policy(%__MODULE__{policy: nil} = state, snapshot) do
    if demanded?(state, snapshot) and not active?(state) do
      replace_session(state, snapshot)
    else
      state = if demanded?(state, snapshot), do: state, else: close(state)
      {:ok, put_policy(state, snapshot)}
    end
  end

  defp apply_policy(%__MODULE__{} = state, snapshot) do
    if state.policy_revision ==
         Snapshot.interval(snapshot, :speech_to_text, state.identity.participant_id) and
         demanded?(state, state.policy) == demanded?(state, snapshot) and
         not activity_authority_changed?(state, snapshot) do
      {:ok, %{state | policy: snapshot}}
    else
      replace_session(state, snapshot)
    end
  end

  defp replace_session(state, snapshot) do
    state = close(state)

    if demanded?(state, snapshot) do
      case start_replacement(state) do
        {:ok, replacement} -> {:ok, put_policy(replacement, snapshot)}
        {:error, _reason} -> {:error, :provider_start_failed, state}
      end
    else
      {:ok, put_policy(state, snapshot)}
    end
  end

  defp put_policy(state, snapshot) do
    %{
      state
      | last_provider_sequence: -1,
        policy: snapshot,
        policy_revision:
          Snapshot.interval(snapshot, :speech_to_text, state.identity.participant_id)
    }
  end

  defp demanded?(state, snapshot) do
    SpeechToTextDemand.required?(
      snapshot,
      state.identity.participant_id,
      state.activity_agent_id
    )
  end

  defp activity_authority_changed?(state, snapshot) do
    SpeechToTextDemand.activity_authority_changed?(
      state.policy,
      snapshot,
      state.identity.participant_id,
      state.activity_agent_id
    )
  end

  defp supported_audio?(state, frame) do
    frame.tenant_id == state.identity.tenant_id and
      frame.room_id == state.identity.room_id and
      frame.incarnation_id == state.identity.incarnation_id and
      frame.participant_id == state.identity.participant_id and
      frame.connection_id == state.identity.connection_id and
      frame.codec == state.media_format.codec and
      frame.sample_rate == state.media_format.sample_rate and
      supported_channels?(state, frame.channels) and
      is_binary(frame.payload) and byte_size(frame.payload) > 0 and
      byte_size(frame.payload) <= @maximum_audio_bytes
  end

  defp initial_demand(options, participant_id, activity_agent_id) do
    case Keyword.fetch(options, :initial_policy) do
      :error ->
        {:ok, true}

      {:ok, snapshot} ->
        if Snapshot.valid?(snapshot),
          do: {:ok, SpeechToTextDemand.required?(snapshot, participant_id, activity_agent_id)},
          else: {:error, :invalid_initial_policy}
    end
  end

  defp build_state(
         options,
         identity,
         owner,
         provider_module,
         provider_options,
         allocation,
         demanded?
       ) do
    with nil <- Keyword.get(options, :transport),
         %Vxpipe.CallEngine.Speech.Scope{} = scope <- Keyword.get(options, :speech_scope),
         true <- Code.ensure_loaded?(provider_module),
         true <- function_exported?(provider_module, :configure, 1),
         {:ok, descriptor} <- provider_module.configure(provider_options),
         :ok <- Descriptor.validate_conversational_stt(descriptor),
         {:ok, session} <-
           start_native_session(
             demanded?,
             scope,
             provider_module,
             provider_options,
             Keyword.get(options, :provider_private, []),
             self()
           ) do
      {:ok,
       %__MODULE__{
         activity_agent_id: Keyword.get(options, :activity_agent_id),
         descriptor: descriptor,
         identity: identity,
         last_provider_sequence: -1,
         media_format: %{
           codec: descriptor.format.encoding,
           sample_rate: descriptor.format.sample_rate,
           channels: descriptor.format.channels
         },
         next_turn_index: 0,
         owner: owner,
         policy: nil,
         policy_revision: nil,
         private_allocation: allocation,
         provider_module: provider_module,
         provider_options: provider_options,
         provider_private: Keyword.get(options, :provider_private, []),
         readiness_generation: make_ref(),
         readiness_status: :preparing,
         scope: scope,
         session: session,
         turn_indexes: %{},
         usage: nil,
         usage_context: Keyword.get(options, :usage)
       }}
    else
      _invalid -> {:error, :provider_start_failed}
    end
  end

  defp start_native_session(false, _scope, _provider, _options, _private, _consumer),
    do: {:ok, nil}

  defp start_native_session(true, scope, provider, options, private, consumer) do
    case Session.start(scope,
           owner: self(),
           consumer: consumer,
           provider: provider,
           options: options,
           private: private,
           usage: false
         ) do
      {:ok, session, :starting} -> {:ok, session}
      {:error, _reason} = error -> error
    end
  end

  defp start_prepared(%__MODULE__{} = state, deadline) do
    case Session.start(state.scope,
           owner: self(),
           consumer: nil,
           lease: self(),
           provider: state.provider_module,
           options: state.provider_options,
           private: state.provider_private,
           start_timeout: max(deadline - System.monotonic_time(:millisecond), 1),
           usage: false
         ) do
      {:ok, session, :starting} -> {:ok, %{state | session: session}}
      {:error, _reason} -> {:error, :provider_start_failed}
    end
  end

  defp start_replacement(%__MODULE__{} = state) do
    case start_native_session(
           true,
           state.scope,
           state.provider_module,
           state.provider_options,
           state.provider_private,
           self()
         ) do
      {:ok, session} -> {:ok, %{state | session: session}}
      {:error, _reason} = error -> error
    end
  end

  defp active?(%__MODULE__{session: session}), do: session != nil
  defp initial_status(%__MODULE__{}), do: :preparing

  defp supported_channels?(%__MODULE__{media_format: format}, channels),
    do: channels == format.channels

  defp semantic_signal(state, %Event{kind: :ready} = event) do
    signal = %Signal{
      kind: :connected,
      provider_sequence: event.sequence,
      request_id: event.provider_request_id
    }

    {:ok, signal, %{state | readiness_status: :ready}}
  end

  defp semantic_signal(state, %Event{kind: :speech_started, turn_ref: turn_ref} = event) do
    turn_index = state.next_turn_index

    signal = %Signal{
      kind: :turn_started,
      provider_sequence: event.sequence,
      provider_turn_index: turn_index,
      request_id: event.provider_request_id,
      text: ""
    }

    {:ok, signal,
     %{
       state
       | next_turn_index: turn_index + 1,
         turn_indexes: Map.put(state.turn_indexes, turn_ref, turn_index)
     }}
  end

  defp semantic_signal(state, %Event{kind: :transcript} = event),
    do: turn_signal(state, event, :transcript_updated)

  defp semantic_signal(state, %Event{kind: :turn_resumed} = event),
    do: turn_signal(state, event, :turn_resumed)

  defp semantic_signal(state, %Event{kind: :eager_turn_ended} = event),
    do: turn_signal(state, event, :eager_turn_ended)

  defp semantic_signal(state, %Event{kind: :turn_ended} = event) do
    with {:ok, signal, state} <- turn_signal(state, event, :turn_ended) do
      signal = %{
        signal
        | end_of_turn_confidence: 1.0,
          trigger: endpointing_trigger(event.endpointing)
      }

      {:ok, signal, %{state | turn_indexes: Map.delete(state.turn_indexes, event.turn_ref)}}
    end
  end

  defp semantic_signal(_state, _event), do: {:error, :unsupported_event}

  defp turn_signal(state, event, kind) do
    case Map.fetch(state.turn_indexes, event.turn_ref) do
      {:ok, turn_index} ->
        {:ok,
         %Signal{
           kind: kind,
           provider_sequence: event.sequence,
           provider_turn_index: turn_index,
           request_id: event.provider_request_id,
           audio_duration_ms: event.audio_duration_ms,
           text: event.text
         }, state}

      :error ->
        {:error, :unknown_turn}
    end
  end

  defp endpointing_trigger(:provider_gap), do: "provider_gap"
  defp endpointing_trigger(:provider_semantic), do: "provider_semantic"
end
