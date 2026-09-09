defmodule Vxpipe.CallEngine.Provider.MorseCodeSTT.Transport do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Provider.SpeechToText.Transport

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}

  @call_timeout 5_000
  @request_id "morse-local"

  @impl true
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def send_audio(transport, audio) when is_binary(audio) do
    GenServer.call(transport, {:send_audio, audio}, @call_timeout)
  end

  @impl true
  def close(transport), do: GenServer.call(transport, :close, @call_timeout)

  @impl true
  def init(options) do
    with %{config: %Config{} = config} <- Keyword.fetch!(options, :connection),
         {:ok, decoder} <- Decoder.new(config) do
      state = %{
        decoder: decoder,
        owner: Keyword.fetch!(options, :owner),
        sequence: 0,
        turn_index: 0
      }

      {:ok, emit_connected(state)}
    else
      _invalid -> {:stop, :invalid_connection_options}
    end
  end

  @impl true
  def handle_call({:send_audio, audio}, _from, state) do
    case Decoder.push(state.decoder, audio) do
      {:ok, decoder, events} ->
        {:reply, :ok, emit_events(events, %{state | decoder: decoder})}

      {:error, reason} ->
        {:reply, :ok, emit_error(reason, state)}
    end
  end

  def handle_call(:close, _from, state) do
    state =
      case Decoder.flush(state.decoder) do
        {:ok, decoder, events} -> emit_events(events, %{state | decoder: decoder})
        {:error, reason} -> emit_error(reason, state)
      end

    {:stop, :normal, :ok, state}
  end

  defp emit_connected(state) do
    message = %{
      "type" => "Connected",
      "request_id" => @request_id,
      "sequence_id" => state.sequence
    }

    emit(message, %{state | sequence: state.sequence + 1})
  end

  defp emit_events(events, state), do: Enum.reduce(events, state, &emit_event/2)

  defp emit_event(:started, state) do
    message = turn_message("StartOfTurn", "", state)
    emit(message, %{state | sequence: state.sequence + 1})
  end

  defp emit_event({:partial, text}, state) do
    message = turn_message("Update", text, state)
    emit(message, %{state | sequence: state.sequence + 1})
  end

  defp emit_event({:final, text}, state) do
    message = turn_message("EndOfTurn", text, state) |> Map.put("trigger", "morse_end_gap")

    state = %{state | sequence: state.sequence + 1, turn_index: state.turn_index + 1}
    emit(message, state)
  end

  defp emit_error(reason, state) do
    message = %{
      "type" => "Error",
      "sequence_id" => state.sequence,
      "code" => error_code(reason)
    }

    emit(message, %{state | sequence: state.sequence + 1})
  end

  defp turn_message(event, text, state) do
    %{
      "type" => "TurnInfo",
      "event" => event,
      "request_id" => @request_id,
      "sequence_id" => state.sequence,
      "turn_index" => state.turn_index,
      "transcript" => text
    }
  end

  defp emit(message, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:message, JSON.encode!(message)}})
    state
  end

  defp error_code(reason) do
    reason
    |> Atom.to_string()
    |> String.upcase()
  end
end
