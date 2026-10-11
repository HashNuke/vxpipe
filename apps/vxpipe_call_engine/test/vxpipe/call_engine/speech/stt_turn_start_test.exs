defmodule Vxpipe.CallEngine.Speech.STTTurnStartTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Event, STTTurnStart}

  defp native!(kind, fields) do
    {:ok, event} = Event.build(kind, fields)
    event
  end

  defp kinds(emissions), do: Enum.map(emissions, &elem(&1, 0))

  defp canonical_refs(emissions) do
    emissions |> Enum.map(fn {_kind, fields} -> Keyword.get(fields, :turn_ref) end) |> Enum.uniq()
  end

  defp assert_outer_valid(emissions) do
    for {kind, fields} <- emissions do
      assert {:ok, _event} = Event.build(kind, fields),
             "coordinator emission must be a valid outer-channel event: #{inspect(kind)}"
    end
  end

  defp start_ref(emissions) do
    assert {:speech_started, fields} = List.first(emissions)
    Keyword.get(fields, :turn_ref)
  end

  test "new/0 defaults to transcript start without local onset" do
    state = STTTurnStart.new()
    assert {:error, :vad_disabled} = STTTurnStart.activity_started(state)
  end

  test "native speech_started is correlation only and never emits" do
    state = STTTurnStart.new()
    provider = make_ref()
    event = native!(:speech_started, turn_ref: provider)

    assert {:ok, state, []} = STTTurnStart.native(state, event)
    assert {:ok, _state, []} = STTTurnStart.native(state, event)
  end

  test "empty interim transcripts are ignored and start nothing" do
    state = STTTurnStart.new()

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:transcript, turn_ref: make_ref(), text: ""))

    assert {:ok, _state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: make_ref(), text: "   \n\t  ")
             )
  end

  test "first nonempty transcript emits start then transcript with one canonical ref" do
    state = STTTurnStart.new()
    provider = make_ref()

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript,
                 turn_ref: provider,
                 text: "hello",
                 provider_request_id: "req-1"
               )
             )

    assert kinds(emissions) == [:speech_started, :transcript]
    assert [canon] = canonical_refs(emissions)
    assert is_reference(canon)
    assert canon != provider
    assert {:transcript, fields} = List.last(emissions)
    assert Keyword.get(fields, :text) == "hello"
    assert Keyword.get(fields, :provider_request_id) == "req-1"
    assert_outer_valid(emissions)
  end

  test "repeated interim text is deduplicated on the same canonical ref" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, first} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "hi"))

    assert kinds(first) == [:speech_started, :transcript]

    assert {:ok, _state, []} =
             STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "hi"))
  end

  test "revised interim text updates the same canonical ref" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, first} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "hel"))

    canon = start_ref(first)

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "hello there")
             )

    assert kinds(emissions) == [:transcript]
    assert [{:transcript, fields}] = emissions
    assert Keyword.get(fields, :turn_ref) == canon
    assert Keyword.get(fields, :text) == "hello there"
    assert_outer_valid(emissions)
  end

  test "hint then transcript for one provider turn produces exactly one start" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, []} =
      STTTurnStart.native(state, native!(:speech_started, turn_ref: provider))

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "hi")
             )

    assert kinds(emissions) == [:speech_started, :transcript]
    assert_outer_valid(emissions)
  end

  test "final-only turn_ended emits start, transcript and end in order" do
    state = STTTurnStart.new()

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: make_ref(),
                 text: "final words",
                 endpointing: :provider_semantic,
                 provider_request_id: "req-final",
                 audio_duration_ms: 1_200
               )
             )

    assert kinds(emissions) == [:speech_started, :transcript, :turn_ended]
    assert [canon] = canonical_refs(emissions)
    assert {:turn_ended, fields} = List.last(emissions)
    assert Keyword.get(fields, :turn_ref) == canon
    assert Keyword.get(fields, :text) == "final words"
    assert Keyword.get(fields, :endpointing) == :provider_semantic
    assert Keyword.get(fields, :provider_request_id) == "req-final"
    assert Keyword.get(fields, :audio_duration_ms) == 1_200
    assert_outer_valid(emissions)
  end

  test "final repeating interim text emits end only without duplicating transcript" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "done"))

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: provider,
                 text: "done",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended]
    assert_outer_valid(emissions)
  end

  test "revised final emits transcript revision then end on the same ref" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, first} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "hel"))

    canon = start_ref(first)

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: provider, text: "hello", endpointing: :provider_gap)
             )

    assert kinds(emissions) == [:transcript, :turn_ended]
    assert [^canon] = canonical_refs(emissions)
    assert_outer_valid(emissions)
  end

  test "vad onset before text emits one early start joined by later transcripts" do
    state = STTTurnStart.new(vad: true)
    provider = make_ref()

    assert {:ok, state, early} = STTTurnStart.activity_started(state)
    assert kinds(early) == [:speech_started]
    assert [acoustic] = canonical_refs(early)
    assert_outer_valid(early)

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: provider))

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "hi")
             )

    assert kinds(emissions) == [:transcript]
    assert [{:transcript, fields}] = emissions
    assert Keyword.get(fields, :turn_ref) == acoustic
    assert_outer_valid(emissions)
  end

  test "text before vad suppresses a duplicate local start" do
    state = STTTurnStart.new(vad: true)
    provider = make_ref()

    {:ok, state, first} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "hi"))

    canon = start_ref(first)
    assert_outer_valid(first)

    assert {:ok, state, []} = STTTurnStart.activity_started(state)

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: provider, text: "hi", endpointing: :provider_gap)
             )

    assert kinds(emissions) == [:turn_ended]
    assert [{:turn_ended, fields}] = emissions
    assert Keyword.get(fields, :turn_ref) == canon
  end

  test "missed vad falls back to transcript start and ordered end" do
    state = STTTurnStart.new(vad: true)
    provider = make_ref()

    {:ok, state, first} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "fallback"))

    assert kinds(first) == [:speech_started, :transcript]

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: provider,
                 text: "fallback",
                 endpointing: :provider_semantic
               )
             )

    assert kinds(emissions) == [:turn_ended]
    assert [canon] = canonical_refs(first ++ emissions)
    assert start_ref(first) == canon
  end

  test "duplicate local starts while a turn is open emit once" do
    state = STTTurnStart.new(vad: true)

    assert {:ok, state, first} = STTTurnStart.activity_started(state)
    assert kinds(first) == [:speech_started]

    assert {:ok, _state, []} = STTTurnStart.activity_started(state)
  end

  test "empty final settles a vad-started turn with no transcript" do
    state = STTTurnStart.new(vad: true)

    {:ok, state, first} = STTTurnStart.activity_started(state)
    canon = start_ref(first)

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: make_ref(), text: "", endpointing: :provider_gap)
             )

    assert kinds(emissions) == [:turn_ended]
    assert [{:turn_ended, fields}] = emissions
    assert Keyword.get(fields, :turn_ref) == canon
    assert Keyword.get(fields, :text) == ""
    assert Keyword.get(fields, :endpointing) == :provider_gap
    assert_outer_valid(emissions)
  end

  test "empty final without a prior start emits nothing" do
    state = STTTurnStart.new()

    assert {:ok, _state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: make_ref(), text: "  ", endpointing: :provider_gap)
             )
  end

  test "eager end before start is held and follows transcript with the same ref" do
    state = STTTurnStart.new()
    provider = make_ref()

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "part",
                 endpointing: :provider_semantic,
                 provider_request_id: "req-eager"
               )
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "part")
             )

    assert kinds(emissions) == [:speech_started, :transcript, :eager_turn_ended]
    assert [canon] = canonical_refs(emissions)
    assert [{:speech_started, _}, {:transcript, _}, {:eager_turn_ended, eager}] = emissions
    assert Keyword.get(eager, :turn_ref) == canon
    assert Keyword.get(eager, :endpointing) == :provider_semantic
    assert Keyword.get(eager, :provider_request_id) == "req-eager"
    assert_outer_valid(emissions)
  end

  test "eager end and resume after start preserve the canonical ref" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, first} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "part"))

    canon = start_ref(first)

    assert {:ok, state, eager} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "part",
                 endpointing: :provider_gap
               )
             )

    assert kinds(eager) == [:eager_turn_ended]
    assert [{:eager_turn_ended, eager_fields}] = eager
    assert Keyword.get(eager_fields, :turn_ref) == canon

    assert {:ok, _state, resumed} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: provider))

    assert kinds(resumed) == [:turn_resumed]
    assert [{:turn_resumed, resume_fields}] = resumed
    assert Keyword.get(resume_fields, :turn_ref) == canon
    assert_outer_valid(eager ++ resumed)
  end

  test "resume before start is held until transcript start" do
    state = STTTurnStart.new()
    provider = make_ref()

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: provider))

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "again")
             )

    assert kinds(emissions) == [:speech_started, :transcript, :turn_resumed]
    assert [canon] = canonical_refs(emissions)
    assert start_ref(emissions) == canon
    assert_outer_valid(emissions)
  end

  test "native hint before vad onset is adopted by local onset" do
    state = STTTurnStart.new(vad: true)
    provider = make_ref()

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: provider))

    assert {:ok, state, acoustic} = STTTurnStart.activity_started(state)
    adopted = start_ref(acoustic)

    assert {:ok, state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "hi")
             )

    assert kinds(emissions) == [:transcript]
    assert [{:transcript, fields}] = emissions
    assert Keyword.get(fields, :turn_ref) == adopted
    assert_outer_valid(emissions)

    assert {:ok, _state, ended} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: provider,
                 text: "hi",
                 endpointing: :provider_gap
               )
             )

    assert kinds(ended) == [:turn_ended]
    assert [{:turn_ended, end_fields}] = ended
    assert Keyword.get(end_fields, :turn_ref) == adopted
    assert_outer_valid(ended)
  end

  test "hint plus blank final in default mode silently closes correlation" do
    state = STTTurnStart.new()
    provider = make_ref()

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: provider))

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: provider,
                 text: "",
                 endpointing: :provider_gap
               )
             )

    assert {:ok, _state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "late")
             )
  end

  test "queued interim plus blank final drains after active settles" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:transcript,
          turn_ref: first_provider,
          text: "alpha",
          provider_request_id: "req-a"
        )
      )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "bravo")
             )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: second_provider,
                 text: "  ",
                 endpointing: :provider_semantic,
                 provider_request_id: "req-b-final"
               )
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "alpha",
                 endpointing: :provider_gap,
                 provider_request_id: "req-a"
               )
             )

    assert kinds(emissions) == [:turn_ended, :speech_started, :transcript, :turn_ended]

    assert [
             {:turn_ended, _},
             {:speech_started, started},
             {:transcript, transcript},
             {:turn_ended, queued_end}
           ] = emissions

    assert Keyword.get(transcript, :text) == "bravo"
    assert Keyword.get(transcript, :turn_ref) == Keyword.get(started, :turn_ref)
    assert Keyword.get(queued_end, :turn_ref) == Keyword.get(started, :turn_ref)
    assert Keyword.get(started, :provider_request_id) == "req-b-final"
    assert Keyword.get(transcript, :provider_request_id) == "req-b-final"
    assert Keyword.get(queued_end, :provider_request_id) == "req-b-final"
    assert_outer_valid(emissions)
  end

  test "queued final seals entry against later partials and controls" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: first_provider, text: "alpha")
      )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "two")
             )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: second_provider,
                 text: "two-final",
                 endpointing: :provider_semantic
               )
             )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "hacked")
             )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: second_provider,
                 text: "hacked",
                 endpointing: :provider_semantic
               )
             )

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: second_provider))

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "alpha",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended, :speech_started, :transcript, :turn_ended]

    assert [
             {:turn_ended, _},
             {:speech_started, _},
             {:transcript, transcript},
             {:turn_ended, _}
           ] = emissions

    assert Keyword.get(transcript, :text) == "two-final"
    assert_outer_valid(emissions)
  end

  test "final-only queued transcript uses final request id" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: first_provider, text: "alpha")
      )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: second_provider,
                 text: "queued-words",
                 endpointing: :provider_semantic,
                 provider_request_id: "req-queued"
               )
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "alpha",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended, :speech_started, :transcript, :turn_ended]

    assert [
             {:turn_ended, _},
             {:speech_started, started},
             {:transcript, transcript},
             {:turn_ended, queued_end}
           ] = emissions

    assert Keyword.get(transcript, :text) == "queued-words"
    assert Keyword.get(transcript, :provider_request_id) == "req-queued"
    assert Keyword.get(started, :provider_request_id) == "req-queued"
    assert Keyword.get(queued_end, :provider_request_id) == "req-queued"
    assert_outer_valid(emissions)
  end

  test "duplicate eager and resume transitions are suppressed" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "part"))

    assert {:ok, state, eager} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "part",
                 endpointing: :provider_gap
               )
             )

    assert kinds(eager) == [:eager_turn_ended]

    assert {:ok, _, []} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "part",
                 endpointing: :provider_gap
               )
             )

    assert {:ok, state, resumed} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: provider))

    assert kinds(resumed) == [:turn_resumed]

    assert {:ok, _, []} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: provider))
  end

  test "per-turn control buffering is bounded" do
    state = STTTurnStart.new()
    provider = make_ref()
    limit = STTTurnStart.max_controls()

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: provider))

    state =
      Enum.reduce(1..limit, state, fn index, acc ->
        kind =
          if rem(index, 2) == 1,
            do: :eager_turn_ended,
            else: :turn_resumed

        event =
          if kind == :eager_turn_ended,
            do: native!(kind, turn_ref: provider, text: "e", endpointing: :provider_gap),
            else: native!(kind, turn_ref: provider)

        {:ok, next, []} = STTTurnStart.native(acc, event)
        next
      end)

    assert {:error, :turn_overflow} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "overflow",
                 endpointing: :provider_gap
               )
             )
  end

  test "eager before any words is held and dropped on no-word settlement" do
    state = STTTurnStart.new(vad: true)

    {:ok, state, _} = STTTurnStart.activity_started(state)
    provider = make_ref()

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "part",
                 endpointing: :provider_gap
               )
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: provider,
                 text: "",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended]
    assert_outer_valid(emissions)
  end

  test "late finals after eviction are ignored and never rebind stale refs" do
    state = STTTurnStart.new(vad: true)
    limit = STTTurnStart.max_turns()

    {state, first_provider} =
      Enum.reduce(1..limit, {state, nil}, fn index, {acc, first} ->
        provider = make_ref()
        text = "turn #{index}"

        {:ok, acc, first_emissions} =
          STTTurnStart.native(acc, native!(:transcript, turn_ref: provider, text: text))

        assert kinds(first_emissions) == [:speech_started, :transcript]

        {:ok, acc, ended} =
          STTTurnStart.native(
            acc,
            native!(:turn_ended, turn_ref: provider, text: text, endpointing: :provider_gap)
          )

        assert kinds(ended) == [:turn_ended]
        if index == 1, do: {acc, provider}, else: {acc, first}
      end)

    assert is_reference(first_provider)

    evicted_provider = make_ref()

    {:ok, state, evicted_start} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: evicted_provider, text: "new turn")
      )

    assert kinds(evicted_start) == [:speech_started, :transcript]
    evicted_canon = start_ref(evicted_start)

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "turn 1",
                 endpointing: :provider_gap
               )
             )

    assert STTTurnStart.pending_count(state) == 1

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: first_provider, text: "turn 1")
             )

    assert STTTurnStart.pending_count(state) == 1

    newer_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:turn_ended,
          turn_ref: evicted_provider,
          text: "new turn",
          endpointing: :provider_gap
        )
      )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: newer_provider, text: "after")
             )

    assert kinds(emissions) == [:speech_started, :transcript]
    refute start_ref(emissions) == evicted_canon
  end

  test "retired tombstones are bounded with fail-closed overflow" do
    assert STTTurnStart.max_retired() >= 4096
    limit = STTTurnStart.max_retired()

    state =
      Enum.reduce(1..limit, STTTurnStart.new(), fn index, acc ->
        provider = make_ref()
        text = "turn #{index}"

        {:ok, acc, first} =
          STTTurnStart.native(acc, native!(:transcript, turn_ref: provider, text: text))

        assert kinds(first) == [:speech_started, :transcript]

        {:ok, acc, ended} =
          STTTurnStart.native(
            acc,
            native!(:turn_ended, turn_ref: provider, text: text, endpointing: :provider_gap)
          )

        assert kinds(ended) == [:turn_ended]
        acc
      end)

    assert {:error, :turn_overflow} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: make_ref()))
  end

  test "all retired events are ignored after settlement" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "words"))

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:turn_ended, turn_ref: provider, text: "words", endpointing: :provider_gap)
      )

    assert {:ok, _, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "words")
             )

    assert {:ok, _, []} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: provider))

    assert {:ok, _, []} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "words",
                 endpointing: :provider_gap
               )
             )

    assert {:ok, _, []} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: provider))

    assert {:ok, _, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: provider, text: "words", endpointing: :provider_gap)
             )
  end

  test "stale final for an older turn cannot settle a newer vad onset" do
    state = STTTurnStart.new(vad: true)
    older = make_ref()

    {:ok, state, _} = STTTurnStart.activity_started(state)

    {:ok, state, _} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: older, text: "older"))

    {:ok, state, ended} =
      STTTurnStart.native(
        state,
        native!(:turn_ended, turn_ref: older, text: "older", endpointing: :provider_gap)
      )

    assert kinds(ended) == [:turn_ended]

    {:ok, state, newer_start} = STTTurnStart.activity_started(state)
    newer = start_ref(newer_start)

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: older, text: "older", endpointing: :provider_gap)
             )

    newer_provider = make_ref()

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: newer_provider, text: "newer")
             )

    assert kinds(emissions) == [:transcript]
    assert [{:transcript, fields}] = emissions
    assert Keyword.get(fields, :turn_ref) == newer
    assert_outer_valid(newer_start ++ emissions)
  end

  test "overlapping provider turns queue behind the active turn with distinct refs" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, first} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: first_provider, text: "one")
      )

    first_canon = start_ref(first)

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "two")
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "one",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended, :speech_started, :transcript]

    assert [{:turn_ended, ended}, {:speech_started, started}, {:transcript, transcript}] =
             emissions

    assert Keyword.get(ended, :turn_ref) == first_canon
    assert Keyword.get(started, :turn_ref) != first_canon
    assert Keyword.get(transcript, :turn_ref) == Keyword.get(started, :turn_ref)
    assert Keyword.get(transcript, :text) == "two"
    assert_outer_valid(emissions)
  end

  test "queued final for a waiting turn drains in order after the active turn ends" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: first_provider, text: "one")
      )

    {:ok, state, []} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: second_provider, text: "two")
      )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: second_provider,
                 text: "two",
                 endpointing: :provider_semantic
               )
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "one",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended, :speech_started, :transcript, :turn_ended]

    assert [
             {:turn_ended, _},
             {:speech_started, started},
             {:transcript, transcript},
             {:turn_ended, queued_end}
           ] = emissions

    assert Keyword.get(transcript, :turn_ref) == Keyword.get(started, :turn_ref)
    assert Keyword.get(queued_end, :turn_ref) == Keyword.get(started, :turn_ref)
    assert Keyword.get(queued_end, :endpointing) == :provider_semantic
    assert_outer_valid(emissions)
  end

  test "no-word vad turn emits start then end with no transcript" do
    state = STTTurnStart.new(vad: true)

    {:ok, state, started} = STTTurnStart.activity_started(state)
    assert kinds(started) == [:speech_started]

    {:ok, _state, emissions} =
      STTTurnStart.native(
        state,
        native!(:turn_ended, turn_ref: make_ref(), text: "", endpointing: :provider_gap)
      )

    assert kinds(emissions) == [:turn_ended]
    assert_outer_valid(emissions)
  end

  test "overflow returns a fixed safe reason when too many turns stay open" do
    state = STTTurnStart.new()
    limit = STTTurnStart.max_turns()

    state =
      Enum.reduce(1..limit, state, fn _, acc ->
        {:ok, next, []} =
          STTTurnStart.native(acc, native!(:speech_started, turn_ref: make_ref()))

        next
      end)

    assert {:error, :turn_overflow} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: make_ref()))
  end

  test "settled turns are reclaimed so sequential calls stay bounded" do
    state = STTTurnStart.new()
    limit = STTTurnStart.max_turns()

    state =
      Enum.reduce(1..(limit * 2), state, fn index, acc ->
        provider = make_ref()
        text = "turn #{index}"

        {:ok, acc, first} =
          STTTurnStart.native(acc, native!(:transcript, turn_ref: provider, text: text))

        assert kinds(first) == [:speech_started, :transcript]

        {:ok, acc, ended} =
          STTTurnStart.native(
            acc,
            native!(:turn_ended, turn_ref: provider, text: text, endpointing: :provider_gap)
          )

        assert kinds(ended) == [:turn_ended]
        acc
      end)

    assert STTTurnStart.pending_count(state) == 0
  end

  test "drained interim stays revisable and finalizable without premature tombstone" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: first_provider, text: "A"))

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "B")
             )

    assert {:ok, state, drained} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "A",
                 endpointing: :provider_gap
               )
             )

    assert kinds(drained) == [:turn_ended, :speech_started, :transcript]
    assert STTTurnStart.pending_count(state) == 1

    assert {:ok, state, revision} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "B revised")
             )

    assert kinds(revision) == [:transcript]

    assert {:ok, state, final} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: second_provider,
                 text: "B revised",
                 endpointing: :provider_gap
               )
             )

    assert kinds(final) == [:turn_ended]
    assert STTTurnStart.pending_count(state) == 0
    assert_outer_valid(drained ++ revision ++ final)
  end

  test "vad onset flushes held eager immediately after first transcript in order" do
    state = STTTurnStart.new(vad: true)
    provider = make_ref()

    {:ok, state, _} = STTTurnStart.activity_started(state)

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "hello",
                 endpointing: :provider_gap
               )
             )

    assert {:ok, state, text} =
             STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "hello"))

    assert kinds(text) == [:transcript, :eager_turn_ended]
    assert_outer_valid(text)

    assert {:ok, state, resume} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: provider))

    assert kinds(resume) == [:turn_resumed]

    assert {:ok, _state, final} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: provider, text: "hello", endpointing: :provider_gap)
             )

    assert kinds(final) == [:turn_ended]
    assert_outer_valid(resume ++ final)
  end

  test "unmapped blank final tombstones ref and ignores late partial, eager, final and hint" do
    state = STTTurnStart.new()
    provider = make_ref()

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: provider, text: "", endpointing: :provider_gap)
             )

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:transcript, turn_ref: provider, text: "late"))

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:eager_turn_ended,
                 turn_ref: provider,
                 text: "late",
                 endpointing: :provider_gap
               )
             )

    assert {:ok, state, []} =
             STTTurnStart.native(state, native!(:turn_resumed, turn_ref: provider))

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: provider, text: "late", endpointing: :provider_gap)
             )

    assert {:ok, _state, []} =
             STTTurnStart.native(state, native!(:speech_started, turn_ref: provider))

    assert STTTurnStart.pending_count(state) == 0
  end

  test "canonical end retains active interim words on blank final" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: provider, text: "Hello, brave world")
      )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: provider,
                 text: "",
                 endpointing: :provider_semantic,
                 provider_request_id: "req-final-blank",
                 audio_duration_ms: 900
               )
             )

    assert kinds(emissions) == [:turn_ended]
    assert [{:turn_ended, fields}] = emissions
    assert Keyword.get(fields, :text) == "Hello, brave world"
    assert Keyword.get(fields, :endpointing) == :provider_semantic
    assert Keyword.get(fields, :provider_request_id) == "req-final-blank"
    assert Keyword.get(fields, :audio_duration_ms) == 900
    assert_outer_valid(emissions)
  end

  test "canonical end retains active interim words on whitespace-only final" do
    state = STTTurnStart.new()
    provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(
        state,
        native!(:transcript, turn_ref: provider, text: "Hello, brave world")
      )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: provider,
                 text: "   ",
                 endpointing: :provider_gap,
                 provider_request_id: "req-final-ws",
                 audio_duration_ms: 901
               )
             )

    assert kinds(emissions) == [:turn_ended]
    assert [{:turn_ended, fields}] = emissions
    assert Keyword.get(fields, :text) == "Hello, brave world"
    assert Keyword.get(fields, :endpointing) == :provider_gap
    assert Keyword.get(fields, :provider_request_id) == "req-final-ws"
    assert Keyword.get(fields, :audio_duration_ms) == 901
    assert_outer_valid(emissions)
  end

  test "canonical end retains queued interim words on blank final drain" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: first_provider, text: "alpha"))

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "bravo words")
             )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: second_provider,
                 text: "",
                 endpointing: :provider_semantic,
                 provider_request_id: "req-b-final",
                 audio_duration_ms: 500
               )
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "alpha",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended, :speech_started, :transcript, :turn_ended]

    assert [
             {:turn_ended, _},
             {:speech_started, started},
             {:transcript, transcript},
             {:turn_ended, queued_end}
           ] = emissions

    assert Keyword.get(transcript, :text) == "bravo words"
    assert Keyword.get(queued_end, :text) == "bravo words"
    assert Keyword.get(queued_end, :turn_ref) == Keyword.get(started, :turn_ref)
    assert Keyword.get(queued_end, :endpointing) == :provider_semantic
    assert Keyword.get(queued_end, :provider_request_id) == "req-b-final"
    assert Keyword.get(queued_end, :audio_duration_ms) == 500
    assert Keyword.get(started, :provider_request_id) == "req-b-final"
    assert Keyword.get(transcript, :provider_request_id) == "req-b-final"
    assert_outer_valid(emissions)
  end

  test "canonical end retains queued interim words on whitespace-only final drain" do
    state = STTTurnStart.new()
    first_provider = make_ref()
    second_provider = make_ref()

    {:ok, state, _} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: first_provider, text: "alpha"))

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: second_provider, text: "bravo words")
             )

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: second_provider,
                 text: "   ",
                 endpointing: :provider_semantic,
                 provider_request_id: "req-b-final-ws",
                 audio_duration_ms: 501
               )
             )

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: "alpha",
                 endpointing: :provider_gap
               )
             )

    assert kinds(emissions) == [:turn_ended, :speech_started, :transcript, :turn_ended]

    assert [
             {:turn_ended, _},
             {:speech_started, started},
             {:transcript, transcript},
             {:turn_ended, queued_end}
           ] = emissions

    assert Keyword.get(transcript, :text) == "bravo words"
    assert Keyword.get(queued_end, :text) == "bravo words"
    assert Keyword.get(queued_end, :turn_ref) == Keyword.get(started, :turn_ref)
    assert Keyword.get(queued_end, :endpointing) == :provider_semantic
    assert Keyword.get(queued_end, :provider_request_id) == "req-b-final-ws"
    assert Keyword.get(queued_end, :audio_duration_ms) == 501
    assert_outer_valid(emissions)
  end

  test "canonical end emits empty final for started no-word acoustic turn" do
    state = STTTurnStart.new(vad: true)

    {:ok, state, started} = STTTurnStart.activity_started(state)
    canon = start_ref(started)

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: make_ref(),
                 text: "",
                 endpointing: :provider_gap,
                 provider_request_id: "req-acoustic",
                 audio_duration_ms: 100
               )
             )

    assert kinds(emissions) == [:turn_ended]
    assert [{:turn_ended, fields}] = emissions
    assert Keyword.get(fields, :turn_ref) == canon
    assert Keyword.get(fields, :text) == ""
    assert Keyword.get(fields, :endpointing) == :provider_gap
    assert Keyword.get(fields, :provider_request_id) == "req-acoustic"
    assert Keyword.get(fields, :audio_duration_ms) == 100
    assert_outer_valid(emissions)
  end

  test "canonical end stays silent for unstarted no-word blank final" do
    state = STTTurnStart.new()
    provider = make_ref()

    assert {:ok, state, []} =
             STTTurnStart.native(
               state,
               native!(:turn_ended, turn_ref: provider, text: "", endpointing: :provider_gap)
             )

    assert STTTurnStart.pending_count(state) == 0

    assert {:ok, _state, []} =
             STTTurnStart.native(
               state,
               native!(:transcript, turn_ref: provider, text: "late")
             )
  end

  test "provider session capacity of eight pending finals plus one active drains in order" do
    state = STTTurnStart.new()
    providers = Enum.map(1..9, fn _ -> make_ref() end)
    texts = Enum.map(1..9, fn index -> "turn #{index}" end)

    state =
      Enum.reduce(providers, state, fn provider, acc ->
        {:ok, next, []} = STTTurnStart.native(acc, native!(:speech_started, turn_ref: provider))
        next
      end)

    [first_provider | queued_providers] = providers
    [first_text | queued_texts] = texts

    {:ok, state, first} =
      STTTurnStart.native(state, native!(:transcript, turn_ref: first_provider, text: first_text))

    assert kinds(first) == [:speech_started, :transcript]
    first_canon = start_ref(first)
    assert_outer_valid(first)

    state =
      Enum.zip(queued_providers, queued_texts)
      |> Enum.reduce(state, fn {provider, text}, acc ->
        {:ok, next, []} =
          STTTurnStart.native(acc, native!(:transcript, turn_ref: provider, text: text))

        {:ok, sealed, []} =
          STTTurnStart.native(
            next,
            native!(:turn_ended, turn_ref: provider, text: text, endpointing: :provider_semantic)
          )

        sealed
      end)

    assert {:ok, _state, emissions} =
             STTTurnStart.native(
               state,
               native!(:turn_ended,
                 turn_ref: first_provider,
                 text: first_text,
                 endpointing: :provider_gap
               )
             )

    expected_kinds =
      [:turn_ended] ++
        Enum.flat_map(queued_texts, fn _ -> [:speech_started, :transcript, :turn_ended] end)

    assert kinds(emissions) == expected_kinds

    [{:turn_ended, first_end} | drained] = emissions
    assert Keyword.get(first_end, :turn_ref) == first_canon
    assert Keyword.get(first_end, :text) == first_text

    chunks = Enum.chunk_every(drained, 3)

    assert Enum.map(chunks, fn [{s, _}, {t, _}, {e, _}] -> {s, t, e} end) ==
             Enum.map(queued_texts, fn _ ->
               {:speech_started, :transcript, :turn_ended}
             end)

    drained_refs =
      Enum.map(chunks, fn [
                            {:speech_started, started},
                            {:transcript, transcript},
                            {:turn_ended, ended}
                          ] ->
        assert Keyword.get(transcript, :turn_ref) == Keyword.get(started, :turn_ref)
        assert Keyword.get(ended, :turn_ref) == Keyword.get(started, :turn_ref)
        Keyword.get(started, :turn_ref)
      end)

    assert Enum.uniq([first_canon | drained_refs]) == [first_canon | drained_refs]

    transcript_texts =
      Enum.map(chunks, fn [_, {:transcript, fields}, _] -> Keyword.get(fields, :text) end)

    assert transcript_texts == queued_texts

    end_texts =
      [Keyword.get(first_end, :text)] ++
        Enum.map(chunks, fn [_, _, {:turn_ended, fields}] -> Keyword.get(fields, :text) end)

    assert end_texts == texts
    assert_outer_valid(emissions)
  end

  test "malformed and unsupported inputs return fixed safe reasons" do
    state = STTTurnStart.new()

    assert {:error, :invalid_event} = STTTurnStart.native(state, :not_an_event)
    assert {:error, :invalid_event} = STTTurnStart.native(state, %Event{})
    assert {:error, :invalid_event} = STTTurnStart.native(state, %Event{kind: :transcript})

    assert {:error, :unsupported_event} =
             STTTurnStart.native(state, native!(:ready, readiness: :initialized))
  end
end
