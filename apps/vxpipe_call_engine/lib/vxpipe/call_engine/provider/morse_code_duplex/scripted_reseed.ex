defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.ScriptedReseed do
  @moduledoc "Resets a manual-clock Morse session for opt-in continuity tests."

  alias Vxpipe.CallEngine.Provider.MorseCode.{Decoder, Encoder}

  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.{
    Hold,
    Output,
    Profile,
    ToolReply
  }

  alias Vxpipe.CallEngine.Speech.Duplex.{OutputSegmenter, TurnInference}

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
