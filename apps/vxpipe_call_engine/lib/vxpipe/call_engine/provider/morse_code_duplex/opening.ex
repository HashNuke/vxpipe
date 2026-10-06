defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Opening do
  @moduledoc "Queues an agent-owned Morse opening without a caller turn or reply prefix."

  alias Vxpipe.CallEngine.Provider.MorseCode.Encoder
  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.{Output, ReplyFlow}
  alias Vxpipe.CallEngine.Speech.{Event, Opening}
  alias Vxpipe.CallEngine.Speech.Duplex.BurstResponses

  def start(state, context, reference, request) do
    with true <- not state.held? and Output.idle?(state.timeline) and state.segments == %{},
         true <- Opening.valid?(request),
         text = text(request),
         {:ok, pcm} <- Encoder.encode(state.config, text),
         {:ok, next} <- ReplyFlow.enqueue(state, %{text: text, pcm: pcm}),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ) do
      {bursts, []} = BurstResponses.input_accepted(next.bursts, context)
      {:reply, :ok, %{next | bursts: bursts, unanswered?: true}}
    else
      false -> {:reply, {:error, :busy}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  defp text(:generated), do: "HELLO"
  defp text({:fixed, text}), do: text
end
