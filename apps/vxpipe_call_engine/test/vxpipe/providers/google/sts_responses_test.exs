defmodule Vxpipe.Providers.Google.STSResponsesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.STSResponses

  test "a later wire response remains independent while earlier playback settles" do
    context = make_ref()
    {state, first} = response(STSResponses.new(), context, "FIRST", <<1, 0>>)
    output = make_ref()
    assert {:ok, state} = STSResponses.grant(state, first.ref, output)
    state = drain_generation(state, first.ref, output)
    assert {:ok, state} = STSResponses.model_end(state)

    {state, second} = response(state, context, "SECOND", <<2, 0>>)
    assert second.ref != first.ref
    assert second.index == first.index + 1
    assert second.context == first.context
    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.model_end(state)
    refute STSResponses.idle?(state)
    assert {:error, :busy} = STSResponses.grant(state, second.ref, make_ref())

    assert {:ok, state} = STSResponses.settle(state, first.ref, output)
    assert STSResponses.fetch(state, first.ref) == :error
    refute STSResponses.idle?(state)
    assert {:ok, pending} = STSResponses.fetch(state, second.ref)
    assert pending.text == "SECOND"
    assert pending.queue == [<<2, 0>>]
    assert pending.generation_done?

    second_output = make_ref()
    assert {:ok, state} = STSResponses.grant(state, second.ref, second_output)
    state = drain_generation(state, second.ref, second_output)
    assert {:ok, state} = STSResponses.settle(state, second.ref, second_output)
    assert STSResponses.idle?(state)
    assert STSResponses.counts(state) == %{records: 0, pending_chunks: 0, text_bytes: 0}
  end

  test "playback settlement cannot retire an unfinished wire generation" do
    {state, first} = response(STSResponses.new(), make_ref(), "RESPONSE", <<1, 0>>)
    output = make_ref()
    assert {:ok, state} = STSResponses.grant(state, first.ref, output)
    state = drain_generation(state, first.ref, output)
    assert {:ok, state} = STSResponses.settle(state, first.ref, output)
    refute STSResponses.idle?(state)
    assert {:ok, %{played?: true, model_done?: false}} = STSResponses.fetch(state, first.ref)
    assert {:ok, state} = STSResponses.model_end(state)
    assert STSResponses.idle?(state)
  end

  test "text-only and thought-only generations never request speech admission" do
    context = make_ref()
    assert {:ok, state, thought} = STSResponses.ensure_wire(STSResponses.new(), context)
    assert {:ok, state} = STSResponses.model_end(state)
    assert STSResponses.idle?(state)
    assert {:ok, state, text} = STSResponses.ensure_wire(state, context)
    assert text.index == thought.index + 1
    assert {:ok, state} = STSResponses.append_text(state, "PRIVATE UNTIL SPOKEN")
    assert {:error, :not_announced} = STSResponses.grant(state, text.ref, make_ref())
    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.model_end(state)
    assert STSResponses.idle?(state)
    assert STSResponses.counts(state).text_bytes == 0
  end

  test "a burst of small wire packets retains ordered PCM within the existing chunk budget" do
    assert {:ok, state, response} = STSResponses.ensure_wire(STSResponses.new(), make_ref())
    packets = Enum.map(1..60, &:binary.copy(<<&1::little-signed-16>>, 2_048))

    state =
      Enum.reduce(packets, state, fn pcm, state ->
        assert {:ok, next, _announcement} = STSResponses.append_audio(state, pcm)
        next
      end)

    assert {:ok, buffered} = STSResponses.fetch(state, response.ref)
    assert IO.iodata_to_binary(buffered.queue) == IO.iodata_to_binary(packets)
    assert STSResponses.counts(state).pending_chunks <= 16
    assert Enum.all?(buffered.queue, &(byte_size(&1) <= 131_072))
    assert {:ok, state} = STSResponses.discard(state, response.ref)
    assert STSResponses.counts(state).pending_chunks == 0
  end

  test "global pending PCM capacity is shared by admitted and later responses" do
    context = make_ref()

    {state, first} =
      response(STSResponses.new(), context, "FIRST", :binary.copy(<<1, 0>>, 65_536))

    assert {:ok, state} = STSResponses.grant(state, first.ref, make_ref())
    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.model_end(state)
    assert {:ok, state, _second} = STSResponses.ensure_wire(state, context)

    state =
      Enum.reduce(2..16, state, fn index, state ->
        assert {:ok, next, _announcement} =
                 STSResponses.append_audio(
                   state,
                   :binary.copy(<<index::little-signed-16>>, 65_536)
                 )

        next
      end)

    assert STSResponses.counts(state).pending_chunks == 16
    assert {:error, :audio_overflow} = STSResponses.append_audio(state, <<17, 0>>)
  end

  test "global retained spoken text capacity includes earlier playback" do
    context = make_ref()

    {state, _first} =
      response(STSResponses.new(), context, String.duplicate("a", 32_768), <<1, 0>>)

    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.model_end(state)
    assert {:ok, state, _second} = STSResponses.ensure_wire(state, context)
    assert {:ok, state} = STSResponses.append_text(state, String.duplicate("b", 32_768))
    assert STSResponses.counts(state).text_bytes == 65_536
    assert {:error, :text_overflow} = STSResponses.append_text(state, "c")
  end

  test "record bounds and immutable origin survive continued generations" do
    context = make_ref()

    state =
      Enum.reduce(1..16, STSResponses.new(), fn index, state ->
        {state, response} = response(state, context, "", <<index::little-signed-16>>)
        assert response.index == index
        assert {:error, :context_mismatch} = STSResponses.ensure_wire(state, make_ref())
        assert {:ok, state} = STSResponses.generation_end(state)
        assert {:ok, state} = STSResponses.model_end(state)
        state
      end)

    assert {:error, :response_overflow} = STSResponses.ensure_wire(state, context)
    assert STSResponses.counts(state).records == 16
  end

  test "stale grants credits and settlements cannot mutate the next response" do
    context = make_ref()
    {state, first} = response(STSResponses.new(), context, "FIRST", <<1, 0>>)
    output = make_ref()
    assert {:ok, state} = STSResponses.grant(state, first.ref, output)
    credit = make_ref()
    assert {:ok, state} = STSResponses.sent_audio(state, first.ref, output, credit)
    assert {:error, :stale_credit} = STSResponses.ack_credit(state, output, make_ref())
    assert {:error, :not_completed} = STSResponses.settle(state, first.ref, output)
    assert {:ok, state} = STSResponses.ack_credit(state, output, credit)
    assert {:error, :stale_credit} = STSResponses.ack_credit(state, output, credit)
    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.completed(state, first.ref, output)
    assert {:ok, state} = STSResponses.model_end(state)
    assert {:ok, state} = STSResponses.settle(state, first.ref, output)

    {state, second} = response(state, context, "SECOND", <<2, 0>>)
    assert {:error, :stale_response} = STSResponses.grant(state, first.ref, make_ref())
    assert {:error, :stale_response} = STSResponses.settle(state, first.ref, output)
    assert {:error, :stale_credit} = STSResponses.ack_credit(state, output, credit)
    assert {:ok, %{queue: [<<2, 0>>], text: "SECOND"}} = STSResponses.fetch(state, second.ref)
  end

  test "discard targets one queued response without interrupting the newer wire owner" do
    context = make_ref()
    {state, first} = response(STSResponses.new(), context, "FIRST", <<1, 0>>)
    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.model_end(state)
    {state, second} = response(state, context, "SECOND", <<2, 0>>)
    assert {:ok, state} = STSResponses.discard(state, first.ref)
    assert STSResponses.fetch(state, first.ref) == :error
    assert {:ok, state} = STSResponses.append_text(state, " TAIL")

    assert {:ok, %{text: "SECOND TAIL", discarded?: false}} =
             STSResponses.fetch(state, second.ref)

    assert STSResponses.counts(state) == %{records: 1, pending_chunks: 1, text_bytes: 11}
  end

  test "discarded current wire stays fenced until its model boundary" do
    {state, response} = response(STSResponses.new(), make_ref(), "DISCARD", <<1, 0>>)
    assert {:ok, state} = STSResponses.discard(state, response.ref)
    assert {:ok, state, nil} = STSResponses.append_audio(state, <<2, 0>>)
    assert {:ok, state} = STSResponses.append_text(state, "STALE")
    refute STSResponses.idle?(state)
    assert STSResponses.counts(state) == %{records: 1, pending_chunks: 0, text_bytes: 0}
    assert {:ok, state} = STSResponses.model_end(state)
    assert STSResponses.idle?(state)
  end

  test "repeated settled responses retire with bounded state and increasing ordinals" do
    context = make_ref()

    Enum.reduce(1..40, STSResponses.new(), fn index, state ->
      {state, response} = response(state, context, "REPLY", <<1, 0>>)
      assert response.index == index
      output = make_ref()
      assert {:ok, state} = STSResponses.grant(state, response.ref, output)
      state = drain_generation(state, response.ref, output)
      assert {:ok, state} = STSResponses.model_end(state)
      assert {:ok, state} = STSResponses.settle(state, response.ref, output)
      assert STSResponses.idle?(state)
      assert STSResponses.counts(state).records == 0
      state
    end)
  end

  test "A's final credit and playback cannot complete B's current wire generation" do
    context = make_ref()
    {state, first} = response(STSResponses.new(), context, "FIRST", <<1, 0>>)
    output = make_ref()
    credit = make_ref()
    assert {:ok, state} = STSResponses.grant(state, first.ref, output)
    assert {:ok, state} = STSResponses.sent_audio(state, first.ref, output, credit)
    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.model_end(state)
    {state, second} = response(state, context, "SECOND", <<2, 0>>)
    assert {:ok, before} = STSResponses.fetch(state, second.ref)
    refute before.generation_done?

    assert {:ok, state} = STSResponses.ack_credit(state, output, credit)
    assert {:ok, state} = STSResponses.completed(state, first.ref, output)
    assert {:ok, state} = STSResponses.settle(state, first.ref, output)
    assert {:ok, ^before} = STSResponses.fetch(state, second.ref)
    assert {:ok, state} = STSResponses.append_text(state, " STILL GENERATING")

    assert {:ok, %{generation_done?: false, text: "SECOND STILL GENERATING"}} =
             STSResponses.fetch(state, second.ref)

    refute STSResponses.idle?(state)
  end

  for model_end <- [:before_settlement, :after_settlement] do
    test "admitted discard keeps credit until model end #{model_end}" do
      context = make_ref()
      {state, first} = response(STSResponses.new(), context, "FIRST", <<1, 0>>)
      assert {:ok, state, nil} = STSResponses.append_audio(state, <<2, 0>>)
      output = make_ref()
      credit = make_ref()
      assert {:ok, state} = STSResponses.grant(state, first.ref, output)
      assert {:ok, state} = STSResponses.sent_audio(state, first.ref, output, credit)
      assert {:ok, state} = STSResponses.discard(state, first.ref)
      assert STSResponses.counts(state) == %{records: 1, pending_chunks: 0, text_bytes: 0}
      assert {:error, :not_completed} = STSResponses.completed(state, first.ref, output)
      assert {:error, :not_completed} = STSResponses.settle(state, first.ref, output)
      assert {:error, :stale_credit} = STSResponses.ack_credit(state, output, make_ref())

      {state, pending} =
        if unquote(model_end) == :before_settlement do
          assert {:ok, state} = STSResponses.model_end(state)
          response(state, context, "SECOND", <<3, 0>>)
        else
          {state, nil}
        end

      assert {:ok, state} = STSResponses.ack_credit(state, output, credit)
      assert {:ok, state} = STSResponses.completed(state, first.ref, output)
      assert {:ok, state} = STSResponses.settle(state, first.ref, output)
      refute STSResponses.idle?(state)

      {state, pending} =
        if pending == nil do
          assert {:ok, %{played?: true, model_done?: false}} =
                   STSResponses.fetch(state, first.ref)

          assert {:ok, state} = STSResponses.model_end(state)
          response(state, context, "SECOND", <<3, 0>>)
        else
          {state, pending}
        end

      assert STSResponses.fetch(state, first.ref) == :error

      assert {:ok, %{queue: [<<3, 0>>], text: "SECOND", generation_done?: false}} =
               STSResponses.fetch(state, pending.ref)
    end
  end

  test "one credited chunk plus 16 pending is allowed and discard restores capacity" do
    context = make_ref()

    {state, first} =
      response(STSResponses.new(), context, String.duplicate("a", 65_536), <<1, 0>>)

    output = make_ref()
    credit = make_ref()
    assert {:ok, state} = STSResponses.grant(state, first.ref, output)
    assert {:ok, state} = STSResponses.sent_audio(state, first.ref, output, credit)

    state =
      Enum.reduce(1..16, state, fn _, state ->
        assert {:ok, state, nil} =
                 STSResponses.append_audio(state, :binary.copy(<<2, 0>>, 65_536))

        state
      end)

    assert {:error, :audio_overflow} = STSResponses.append_audio(state, <<3, 0>>)
    assert {:error, :text_overflow} = STSResponses.append_text(state, "x")
    assert {:ok, state} = STSResponses.discard(state, first.ref)
    assert {:ok, state} = STSResponses.model_end(state)
    {state, second} = response(state, context, String.duplicate("b", 65_536), <<4, 0>>)
    assert {:ok, state} = STSResponses.ack_credit(state, output, credit)
    assert {:ok, state} = STSResponses.completed(state, first.ref, output)
    assert {:ok, state} = STSResponses.settle(state, first.ref, output)
    assert STSResponses.counts(state) == %{records: 1, pending_chunks: 1, text_bytes: 65_536}
    assert {:ok, %{queue: [<<4, 0>>]}} = STSResponses.fetch(state, second.ref)
  end

  test "discarded completed-model records release capacity without recycling their ordinal" do
    context = make_ref()

    {state, first} =
      Enum.reduce(1..16, {STSResponses.new(), nil}, fn _, {state, first} ->
        {state, response} = response(state, context, "REPLY", <<1, 0>>)
        assert {:ok, state} = STSResponses.generation_end(state)
        assert {:ok, state} = STSResponses.model_end(state)
        {state, first || response}
      end)

    assert {:error, :response_overflow} = STSResponses.ensure_wire(state, context)
    assert {:ok, state} = STSResponses.discard(state, first.ref)
    assert {:ok, state, response} = STSResponses.ensure_wire(state, context)
    assert response.index == 17
    assert response.ref != first.ref
    assert {:ok, _state, _announcement} = STSResponses.append_audio(state, <<2, 0>>)
  end

  test "the final bounded ordinal is never reused after retirement" do
    context = make_ref()
    maximum = 9_223_372_036_854_775_807
    state = %STSResponses{last_index: maximum - 1}
    assert {:ok, state, response} = STSResponses.ensure_wire(state, context)
    assert response.index == maximum
    assert {:ok, state} = STSResponses.model_end(state)
    assert STSResponses.idle?(state)
    assert {:error, :response_overflow} = STSResponses.ensure_wire(state, context)
  end

  defp response(state, context, text, pcm) do
    assert {:ok, state, response} = STSResponses.ensure_wire(state, context)
    assert {:ok, state} = STSResponses.append_text(state, text)
    assert {:ok, state, announcement} = STSResponses.append_audio(state, pcm)
    assert announcement == Map.take(response, [:ref, :index, :context])
    {state, response}
  end

  defp drain_generation(state, turn, output) do
    credit = make_ref()
    assert {:ok, state} = STSResponses.sent_audio(state, turn, output, credit)
    assert {:ok, state} = STSResponses.ack_credit(state, output, credit)
    assert {:ok, state} = STSResponses.generation_end(state)
    assert {:ok, state} = STSResponses.completed(state, turn, output)
    state
  end
end
