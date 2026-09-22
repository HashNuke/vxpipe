defmodule Vxpipe.Providers.Google.STSOutputTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.STSOutput

  for admitted? <- [false, true] do
    test "#{if admitted?, do: "admitted", else: "pre-admission"} output retains at most 16 pending chunks in FIFO order" do
      chunks = for index <- 1..16, do: <<index::little-signed-16>>
      state = %{output: nil, audio_buffer: [], generation_pending_done?: false}

      state =
        if unquote(admitted?),
          do: STSOutput.open_output(state, make_ref(), make_ref()),
          else: state

      state =
        Enum.reduce(chunks, state, fn chunk, state ->
          assert {:ok, next} = STSOutput.buffer_audio(state, chunk)
          next
        end)

      actual = if unquote(admitted?), do: state.output.queue, else: state.audio_buffer
      assert actual == chunks
      assert {:error, :session_failed} = STSOutput.buffer_audio(state, <<17, 0>>)
    end
  end

  test "opening output transfers the pending buffer without adding another allowance" do
    state = %{
      output: nil,
      audio_buffer: List.duplicate(<<1, 0>>, 16),
      generation_pending_done?: false
    }

    state = STSOutput.open_output(state, make_ref(), make_ref())
    assert state.audio_buffer == []
    assert length(state.output.queue) == 16
    assert {:error, :session_failed} = STSOutput.buffer_audio(state, <<2, 0>>)
  end
end
