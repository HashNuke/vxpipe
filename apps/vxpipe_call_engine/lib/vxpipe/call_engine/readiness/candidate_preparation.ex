defmodule Vxpipe.CallEngine.Readiness.CandidatePreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.ConnectionReadiness
  alias Vxpipe.CallEngine.Readiness.ResourceQuery
  alias Vxpipe.CallEngine.{RoomMixer, TranscriptRouter}

  def prepare(captured, options) do
    state = %{
      captured: captured,
      options: options,
      bindings: %{},
      subscriptions: %{},
      speech: %{},
      resources: [],
      connections: %{},
      preparations: []
    }

    [
      &capture_bindings/1,
      &prepare_mixer/1,
      &prepare_router/1,
      &prepare_speech/1,
      &prepare_connections/1,
      &observe_other_resources/1
    ]
    |> Enum.reduce_while({:ok, state}, fn step, {:ok, state} ->
      case safely(step, state) do
        {:ok, state} ->
          {:cont, {:ok, state}}

        {:error, reason, state} ->
          {:halt, {:error, reason, state.preparations}}
      end
    end)
  end

  def validate_options(options) do
    owner = Keyword.get(options, :owner)
    attempt = Keyword.get(options, :attempt_id)
    deadline = Keyword.get(options, :deadline_ms)
    generation = Keyword.get(options, :generation)

    if is_pid(owner) and is_binary(attempt) and byte_size(attempt) in 1..128 and
         is_integer(deadline) and deadline > System.monotonic_time(:millisecond) and
         is_integer(generation) and generation > 0, do: :ok, else: {:error, :invalid_preparation}
  end

  def validate_attempt(%{binding: %{attempt: nil}}, _options), do: :ok

  def validate_attempt(captured, options) do
    attempt = captured.binding.attempt

    if attempt.id == Keyword.fetch!(options, :attempt_id) and
         attempt.deadline_ms == Keyword.fetch!(options, :deadline_ms),
       do: :ok,
       else: {:error, :wrong_attempt}
  end

  defp capture_bindings(state) do
    each_connection(state, fn id, request, state ->
      with {:ok, binding} <-
             ConnectionReadiness.capture(request.instance, identity(state, id, request)),
           :ok <- validate_subscription(binding, request) do
        {:ok, %{state | bindings: Map.put(state.bindings, id, binding)}}
      else
        {:error, reason} -> {:error, failure(:media_connection, request, reason), state}
      end
    end)
  end

  defp validate_subscription(binding, request) do
    if Keyword.fetch!(request.demand, :room_output?) and
         not is_list(Map.get(binding, :policy_subscription)),
       do: {:error, :missing_prepared_subscription},
       else: :ok
  end

  defp prepare_mixer(state) do
    subscriptions =
      for {id, request} <- state.captured.inventory.connections,
          Keyword.fetch!(request.demand, :room_output?),
          do: Map.fetch!(state.bindings, id).policy_subscription

    mixer = state.captured.room.room_mixer
    options = Keyword.put(state.options, :subscriptions, subscriptions)

    case RoomMixer.prepare_policy(mixer, state.captured.candidate, options) do
      {:ok, prepared} ->
        state = remember(state, RoomMixer, mixer, prepared)
        {:ok, %{state | subscriptions: prepared.subscriptions}}

      {:error, reason} ->
        {:error, %{kind: :room_mixer, scope: :room, reason: reason}, state}
    end
  end

  defp prepare_router(state) do
    router = state.captured.room.transcript_router

    case TranscriptRouter.prepare_policy(router, state.captured.candidate, state.options) do
      {:ok, prepared} ->
        {:ok, remember(state, TranscriptRouter, router, prepared)}

      {:error, reason} ->
        {:error, %{kind: :transcript_router, scope: :room, reason: reason}, state}
    end
  end

  defp prepare_speech(state) do
    each_connection(state, fn id, request, state ->
      speech = Map.fetch!(state.captured.binding.connections, id).speech_to_text

      case speech do
        %{capability: capability} when is_pid(capability) ->
          prepare_speech_connection(id, request, capability, state)

        _missing ->
          if Keyword.fetch!(request.demand, :speech_to_text?),
            do: {:error, failure(:speech_to_text, request, :missing), state},
            else: {:ok, state}
      end
    end)
  end

  defp prepare_speech_connection(id, request, capability, state) do
    case SpeechToText.prepare_policy(capability, state.captured.candidate, state.options) do
      {:ok, prepared} ->
        state = remember(state, SpeechToText, capability, prepared)
        provider = List.first(prepared.resources)
        {:ok, %{state | speech: Map.put(state.speech, id, provider)}}

      {:error, reason} ->
        {:error, failure(:speech_to_text, request, reason), state}
    end
  end

  defp prepare_connections(state) do
    each_connection(state, fn id, request, state ->
      subscription = Map.get(state.bindings, id).policy_subscription
      key = if subscription, do: Keyword.fetch!(subscription, :id)

      options =
        state.options
        |> Keyword.put(:subscription, Map.get(state.subscriptions, key))
        |> Keyword.put(:speech_to_text, Map.get(state.speech, id))

      case ConnectionReadiness.prepare_candidate(
             request.instance,
             identity(state, id, request),
             state.captured.candidate,
             request.demand,
             options
           ) do
        {:ok, graph} ->
          {:ok,
           %{
             state
             | connections: Map.put(state.connections, id, graph),
               resources: state.resources ++ graph.resources,
               preparations: state.preparations ++ graph.preparations
           }}

        {:error, reason} ->
          {:error, failure(:media_connection, request, reason), state}
      end
    end)
  end

  defp observe_other_resources(state) do
    room =
      for {kind, instance} <- state.captured.room,
          kind not in [:recording, :room_mixer, :transcript_router],
          do: {kind, :room, instance}

    participants =
      for {id, capabilities} <- state.captured.participants,
          {kind, instance} <- capabilities,
          do: {kind, {:participant, id}, instance}

    Enum.reduce_while(Enum.sort(room ++ participants), {:ok, state}, fn {kind, scope, instance},
                                                                        {:ok, state} ->
      case ResourceQuery.observe(kind, scope, instance, state.captured.candidate.snapshot) do
        {:ok, resource} -> {:cont, {:ok, %{state | resources: state.resources ++ [resource]}}}
        {:error, reason} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp remember(state, adapter, instance, prepared),
    do: %{
      state
      | resources: state.resources ++ prepared.resources,
        preparations:
          state.preparations ++ [%{adapter: adapter, instance: instance, token: prepared.token}]
    }

  defp each_connection(state, callback) do
    Enum.reduce_while(Enum.sort(state.captured.inventory.connections), {:ok, state}, fn {id,
                                                                                         request},
                                                                                        {:ok,
                                                                                         state} ->
      case callback.(id, request, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _reason, _state} = error -> {:halt, error}
      end
    end)
  end

  defp identity(state, id, request) do
    state.captured.identity
    |> Map.take([:tenant_id, :room_id, :incarnation_id])
    |> Map.merge(%{participant_id: request.participant_id, connection_id: id})
  end

  defp failure(kind, request, reason),
    do: %{kind: kind, scope: {:participant, request.participant_id}, reason: reason}

  defp safely(step, state) do
    step.(state)
  rescue
    _exception -> {:error, :unavailable, state}
  catch
    _kind, _reason -> {:error, :unavailable, state}
  end
end
