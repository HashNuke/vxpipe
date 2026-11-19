defmodule Vxpipe.CallEngine.Diagnostics.ScribeReplay do
  @moduledoc """
  Offline fixture runner through the real continuous Scribe adapter. Offsets are
  supplied trace times, not measured wall-clock provider latency. No network or
  provider request is made; only semantic end events can establish an endpoint.
  """
  alias Vxpipe.CallEngine.Diagnostics.ReplayTransport
  alias Vxpipe.CallEngine.Speech.{Event, Session}
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}

  def run(scope, steps, options \\ []) do
    token = make_ref()

    with :ok <- validate_steps(steps),
         {:ok, config} <- Scribe.new(api_key: "offline-fixture", commit_strategy: :vad),
         {:ok, session, :starting} <-
           Session.start(scope,
             provider: STTSession,
             options: [commit_strategy: :vad],
             private: [
               config: config,
               wire_module: ReplayTransport,
               wire_options: [observer: self(), token: token],
               draft_flush_gap_ms: Keyword.get(options, :draft_flush_gap_ms, 5_000)
             ]
           ) do
      try do
        replay(session, steps, Keyword.get(options, :pcm, <<>>), token)
      after
        close(session)
      end
    end
  catch
    :exit, _reason -> {:error, :replay_failed}
  end

  defp replay(session, steps, pcm, token) do
    with {:ok, wire} <- await_wire(token),
         :ok <- ReplayTransport.deliver(wire, {:ready, "offline-fixture"}),
         :ok <- await_ready(session),
         :ok <- audio(session, pcm) do
      initial = %{session: session, wire: wire, current: nil, current_ref: nil, turns: []}

      result =
        Enum.reduce_while(steps, {:ok, initial}, fn {offset, event}, {:ok, state} ->
          case step(state, event, offset) do
            {:ok, next} -> {:cont, {:ok, next}}
            error -> {:halt, error}
          end
        end)

      with {:ok, state} <- result do
        turns = if state.current, do: [state.current | state.turns], else: state.turns
        {:ok, Enum.reverse(turns)}
      end
    end
  end

  defp step(state, :await_manual_commit, offset) do
    wire = state.wire
    turn = state.current_ref

    receive do
      {:diagnostic_replay_commit, ^wire, ^turn} when not is_nil(state.current) ->
        {:ok, %{state | current: Map.put(state.current, :manual_commit_sent, offset)}}
    after
      1_000 -> {:error, :missing_manual_commit}
    end
  end

  defp step(state, {kind, text}, offset) do
    :ok = ReplayTransport.deliver(state.wire, {kind, text})
    _ = :sys.get_state(Session.provider(state.session), 1_000)
    state = drain(state, offset)

    current =
      if kind == :segment and String.trim(text) != "" and state.current != nil,
        do: Map.put(state.current, :provider_text_commit, offset),
        else: state.current

    {:ok, %{state | current: current}}
  end

  defp drain(state, offset) do
    session = state.session

    receive do
      {:vxpipe_speech, %Event{session: ^session} = event} ->
        :ok = Session.ack(session, event)

        state =
          case event.kind do
            :speech_started ->
              :ok = ReplayTransport.tag_turn(state.wire, event.turn_ref)
              %{state | current: %{}, current_ref: event.turn_ref}

            :turn_ended ->
              landmarks =
                state.current
                |> Map.put(:provider_end_received, offset)
                |> Map.put(:adapter_end_emitted, offset)

              :ok = ReplayTransport.tag_turn(state.wire, nil)
              %{state | current: nil, current_ref: nil, turns: [landmarks | state.turns]}

            _other ->
              state
          end

        drain(state, offset)
    after
      0 -> state
    end
  end

  defp await_wire(token) do
    receive do
      {:diagnostic_replay_wire, ^token, wire} -> {:ok, wire}
    after
      1_000 -> {:error, :replay_not_ready}
    end
  end

  defp await_ready(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :ready} = event} ->
        Session.ack(session, event)
    after
      1_000 -> {:error, :replay_not_ready}
    end
  end

  defp audio(_session, <<>>), do: :ok

  defp audio(session, pcm)
       when is_binary(pcm) and rem(byte_size(pcm), 2) == 0 and byte_size(pcm) <= 9_600_000 do
    size = min(byte_size(pcm), 32_000)
    <<chunk::binary-size(size), rest::binary>> = pcm
    with :ok <- Session.push_audio(session, chunk), do: audio(session, rest)
  end

  defp audio(_session, _pcm), do: {:error, :invalid_replay_audio}

  defp validate_steps(steps) when is_list(steps) and length(steps) in 1..1_000 do
    Enum.reduce_while(steps, {:ok, 0}, fn
      {offset, event}, {:ok, previous}
      when is_integer(offset) and offset >= previous and offset <= 604_800_000_000 ->
        if valid_event?(event),
          do: {:cont, {:ok, offset}},
          else: {:halt, {:error, :invalid_replay_steps}}

      _invalid, _acc ->
        {:halt, {:error, :invalid_replay_steps}}
    end)
    |> case do
      {:ok, _offset} -> :ok
      error -> error
    end
  end

  defp validate_steps(_steps), do: {:error, :invalid_replay_steps}
  defp valid_event?(:await_manual_commit), do: true

  defp valid_event?({kind, text}) when kind in [:partial, :segment],
    do: is_binary(text) and byte_size(text) <= 65_536 and String.valid?(text)

  defp valid_event?(_event), do: false

  defp close(session) do
    Session.close(session)
  catch
    :exit, _reason -> :ok
  end
end
