defmodule Vxpipe.Providers.ElevenLabs.RealtimeWatchdog do
  @moduledoc false

  @timeout 30_000

  # Each fingerprint describes progress on one obligation. Input PCM, unrelated
  # responses and delivery credit cannot renew a provider obligation.
  def sync(state) do
    obligations =
      state
      |> caller_obligations()
      |> Map.merge(native_obligations(state))
      |> Map.merge(response_obligations(state))

    Enum.each(state.deadlines, fn {key, deadline} ->
      if Map.get(obligations, key) != deadline.progress,
        do: Process.cancel_timer(deadline.timer)
    end)

    deadlines =
      Map.new(obligations, fn {key, progress} ->
        deadline =
          case Map.get(state.deadlines, key) do
            %{progress: ^progress} = existing -> existing
            _changed -> start(key, progress)
          end

        {key, deadline}
      end)

    %{state | deadlines: deadlines}
  end

  def current?(state, key, ref) do
    case Map.get(state.deadlines, key) do
      %{ref: ^ref} -> true
      _stale -> false
    end
  end

  defp start(key, progress) do
    ref = make_ref()
    timer = Process.send_after(self(), {:realtime_timeout, key, ref}, @timeout)
    %{ref: ref, timer: timer, progress: progress}
  end

  defp caller_obligations(state) do
    for {id, %{stopped?: true, text: nil} = caller} <- state.callers,
        into: %{},
        do: {{:caller, id}, caller.turn}
  end

  defp native_obligations(%{native_origin: %{turn: turn}, active: nil} = state) do
    if Enum.any?(state.callers, fn {_id, caller} -> not caller.stopped? end),
      do: %{},
      else: %{{:native, turn} => :creation}
  end

  defp native_obligations(_state), do: %{}

  defp response_obligations(state) do
    Enum.reduce(state.responses, %{}, fn {token, response}, obligations ->
      obligations =
        case provider_progress(response, token == state.active) do
          nil -> obligations
          progress -> Map.put(obligations, {:response, token}, progress)
        end

      if response.awaiting,
        do: Map.put(obligations, {:credit, token}, response.awaiting),
        else: obligations
    end)
  end

  defp provider_progress(%{id: nil}, true), do: :creation

  defp provider_progress(%{interrupted?: true, done?: false}, _active?),
    do: :cancellation

  defp provider_progress(%{done?: false, id: id} = response, _active?) when is_binary(id),
    do: {:generation, response.audio_sequence, response.text, MapSet.size(response.tool_ids)}

  defp provider_progress(
         %{done?: true, announced?: true, interrupted?: false, text: nil},
         _active?
       ),
       do: :transcript

  defp provider_progress(_response, _active?), do: nil
end
