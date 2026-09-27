defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.ScriptedReseed do
  @moduledoc "Resets a manual-clock Morse session for opt-in continuity tests."

  alias Vxpipe.CallEngine.Provider.MorseCode.{Decoder, Encoder}

  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.{
    Hold,
    Output,
    Profile,
    SegmentStore,
    ToolReply
  }

  alias Vxpipe.CallEngine.Speech.Duplex.{OutputSegmenter, PublishedHistory, TurnInference}
  alias Vxpipe.CallEngine.Speech.ReseedHistoryBarrier

  @barrier_timeout 4_000

  def begin(state, from, reason, resume?) do
    reference = ReseedHistoryBarrier.request(state.channel)
    timer = Process.send_after(self(), {:reseed_barrier_timeout, reference}, @barrier_timeout)
    pending = %{from: from, reason: reason, resume?: resume?, reference: reference, timer: timer}
    {:noreply, %{state | pending_reseed: pending}}
  end

  def confirm(state, pending) do
    Process.cancel_timer(pending.timer)
    seeded_history = PublishedHistory.input(state.history)

    case state |> SegmentStore.drain_all() |> reset() |> queue_prompt(pending.resume?) do
      {:ok, state} ->
        GenServer.reply(
          pending.from,
          {:ok,
           %{reason: pending.reason, seeded_history: seeded_history, resume?: pending.resume?}}
        )

        {:noreply, %{state | pending_reseed: nil}}

      _failure ->
        GenServer.reply(pending.from, {:error, :reseed_failed})
        {:stop, {:shutdown, :reseed_failed}, state}
    end
  end

  def timeout(state, pending) do
    GenServer.reply(pending.from, {:error, :reseed_failed})
    {:stop, {:shutdown, :reseed_failed}, state}
  end

  def reset(state) do
    {:ok, decoder} = Decoder.new(state.config)
    {:ok, inference} = TurnInference.new(gap_ms: state.inference.gap_ms)
    {:ok, segmenter} = OutputSegmenter.new(Profile.segmenter_options(state.config))

    %{
      state
      | decoder: decoder,
        inference: inference,
        segmenter: segmenter,
        timeline: Output.new(state.timeline.leading_silence, state.timeline.trailing_silence),
        input_ms: 0,
        last_partial: "",
        last_fragment_end_ms: nil,
        reseed_attempted?: true,
        unanswered?: false,
        clock_origin_ms: System.monotonic_time(:millisecond),
        emitted_frames: 0,
        clock_generation: make_ref(),
        clock_timer: nil
    }
  end

  def queue_prompt(state, false), do: {:ok, state}

  def queue_prompt(state, true) do
    last_caller =
      state.history.entries
      |> Enum.reverse()
      |> Enum.find_value(fn
        {:caller, text, _tokens} -> text
        _other -> nil
      end)

    continuation =
      case ToolReply.trigger(last_caller || "") do
        :not_a_tool -> last_caller || ""
        {:tool, _name, _arguments} -> ""
      end

    with {:ok, text} <- ToolReply.text(state.config, "LINE CUT OUT " <> continuation),
         {:ok, pcm} <- Encoder.encode(state.config, text) do
      Hold.queue_tool_reply(state, %{text: text, pcm: pcm})
    end
  end
end
