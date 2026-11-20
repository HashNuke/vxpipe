defmodule Vxpipe.CallEngine.TestResponseTrace do
  @moduledoc "Bounded, isolated room completion/dispatch tracing for configured measurements."
  use GenServer
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, TextCapability}
  alias Vxpipe.CallEngine.Event.{ParticipantTurnCompleted, AgentSpeechStarted}
  alias Vxpipe.CallEngine.Command.SendText

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}

  def snapshot(pid), do: GenServer.call(pid, :snapshot, 5_000)

  @impl true
  def init(options) do
    rooms = Keyword.fetch!(options, :rooms) |> Enum.uniq()
    maximum = Keyword.fetch!(options, :maximum_events)
    true = rooms != [] and Enum.all?(rooms, &is_pid/1) and is_integer(maximum) and maximum > 0
    Code.ensure_loaded!(EventPublisher)
    Code.ensure_loaded!(TextCapability)
    session = :trace.session_create(__MODULE__, self(), [])

    identity = %{
      room_id: :"$1",
      incarnation_id: :"$2",
      participant_id: :"$3",
      connection_id: :"$4",
      correlation_id: :"$5"
    }

    completion =
      Map.merge(identity, %{
        __struct__: ParticipantTurnCompleted,
        command_id: :"$6",
        modality: :audio
      })

    egress =
      identity
      |> Map.delete(:participant_id)
      |> Map.merge(%{
        __struct__: AgentSpeechStarted,
        source_participant_id: :"$3",
        command_id: :"$6"
      })

    command = Map.merge(identity, %{__struct__: SendText, id: :"$6"})

    1 =
      :trace.function(
        session,
        {EventPublisher, :publish, 4},
        [
          {[:_, :_, completion, :_], [], message(:completed)},
          {[:_, :_, egress, [source_policy: :_, payload: %{"output_id" => :"$7"}]], [],
           [{:message, {{:egress_ack, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7"}}}]}
        ],
        [:local]
      )

    1 =
      :trace.function(
        session,
        {TextCapability, :respond, 2},
        [{[:_, command], [], message(:dispatched)}],
        [:local]
      )

    for room <- rooms,
        do: 1 = :trace.process(session, room, true, [:call, :arity, :monotonic_timestamp])

    {:ok,
     %{
       session: session,
       rooms: rooms,
       maximum: maximum,
       count: 0,
       events: [],
       error: nil,
       pending: nil,
       fences: MapSet.new()
     }}
  end

  defp message(stage), do: [{:message, {{stage, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6"}}}]

  @impl true
  def handle_call(:snapshot, from, %{pending: nil} = state) do
    # Fence exact PIDs, including exited authorities; :all only covers live tracees.
    fences = MapSet.new(state.rooms, &:trace.delivered(state.session, &1))
    {:noreply, %{state | pending: from, fences: fences}}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, {:error, :snapshot_pending}, state}

  @impl true
  def handle_info(
        {:trace_ts, pid, :call, mfa,
         {stage, room, incarnation, participant, connection, correlation, command, output}, ns},
        state
      )
      when stage in [:egress_ack] do
    {:noreply, next} =
      handle_info(
        {:trace_ts, pid, :call, mfa,
         {stage, room, incarnation, participant, connection, correlation, command}, ns},
        state
      )

    next =
      if next.count > state.count do
        [event | rest] = next.events
        %{next | events: [Map.put(event, :output_id, output) | rest]}
      else
        next
      end

    {:noreply, next}
  end

  def handle_info(
        {:trace_ts, pid, :call, mfa,
         {stage, room, incarnation, participant, connection, correlation, command}, ns},
        state
      )
      when stage in [:completed, :dispatched, :egress_ack] and is_integer(ns) do
    expected =
      if stage != :dispatched,
        do: {EventPublisher, :publish, 4},
        else: {TextCapability, :respond, 2}

    cond do
      pid not in state.rooms or mfa != expected ->
        {:noreply, %{state | error: :unexpected_trace}}

      state.count >= state.maximum ->
        {:noreply, %{state | error: :overflow}}

      true ->
        event = %{
          stage: stage,
          room_id: room,
          incarnation_id: incarnation,
          participant_id: participant,
          connection_id: connection,
          correlation_id: correlation,
          command_id: command,
          at_us: System.convert_time_unit(ns, :nanosecond, :microsecond)
        }

        {:noreply, %{state | count: state.count + 1, events: [event | state.events]}}
    end
  end

  def handle_info({:trace_delivered, _pid, reference}, state) do
    if MapSet.member?(state.fences, reference) do
      remaining = MapSet.delete(state.fences, reference)

      if MapSet.size(remaining) == 0 do
        reply = if state.error, do: {:error, state.error}, else: {:ok, Enum.reverse(state.events)}
        GenServer.reply(state.pending, reply)
        {:noreply, %{state | fences: remaining, pending: nil}}
      else
        {:noreply, %{state | fences: remaining}}
      end
    else
      {:noreply, %{state | error: :unexpected_fence}}
    end
  end

  def handle_info(_unexpected, state), do: {:noreply, %{state | error: :unexpected_trace}}

  @impl true
  def terminate(_reason, state), do: :trace.session_destroy(state.session)
end
