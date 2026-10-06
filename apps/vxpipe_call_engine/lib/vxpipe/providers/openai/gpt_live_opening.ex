defmodule Vxpipe.Providers.OpenAI.GPTLiveOpening do
  @moduledoc "Agent-owned GPT-Live greeting commands and their accepted response origin."

  alias Vxpipe.CallEngine.Speech.Duplex.{BurstResponses, OutputSegmenter}
  alias Vxpipe.CallEngine.Speech.Opening
  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveFixedOpening}

  def start(state, _context, _reference, _opening) when state.opening_started?,
    do: {:reply, {:error, :busy}, state}

  def start(state, context, _reference, opening) do
    event_id = "opening_" <> Integer.to_string(System.unique_integer([:positive]))

    with true <- Opening.valid?(opening),
         true <- state.segments == %{} and not OutputSegmenter.burst?(state.segmenter),
         {:ok, command} <- GPTLive.instructions(cue(opening)),
         :ok <-
           state.wire_module.send_control(
             state.wire,
             JSON.encode!(Map.put(command, "event_id", event_id))
           ) do
      {bursts, []} = BurstResponses.input_accepted(state.bursts, context)

      fixed =
        case opening do
          {:fixed, text} -> GPTLiveFixedOpening.new(state.segmenter, text)
          :generated -> nil
        end

      {:reply, :ok,
       %{
         state
         | latest_context: context,
           bursts: bursts,
           opening_started?: true,
           unanswered?: true,
           fixed_opening: fixed,
           opening_context: context
       }}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def burst_opened(state, reference) do
    latest = BurstResponses.latest_context(state.bursts)
    {bursts, []} = BurstResponses.input_accepted(state.bursts, state.opening_context || latest)

    case BurstResponses.burst_opened(bursts, reference) do
      {:error, _reason} = error ->
        {state, error}

      {bursts, actions} ->
        {bursts, []} = BurstResponses.input_accepted(bursts, latest)
        {%{state | opening_context: nil}, {bursts, actions}}
    end
  end

  def decode(state, payload) do
    case {state.fixed_opening, GPTLive.decode(payload)} do
      {nil, result} -> result
      {_opening, {:ok, {:input_fragment, _fragment}}} -> {:ok, :opening_interrupted}
      {_opening, {:ok, {:delegation, _id, _target, _response_id}}} -> {:ok, :opening_interrupted}
      {_opening, result} -> result
    end
  end

  defp cue(:generated),
    do:
      "Begin the conversation now with an opening based on your system instructions, then pause and listen."

  defp cue({:fixed, text}),
    do:
      "Begin the conversation now. Say exactly the following text, with no additions, then pause and listen: " <>
        text
end
