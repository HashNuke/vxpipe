defmodule Vxpipe.AgentRuntime.Session.OutstandingOutputs do
  @moduledoc false

  @maximum_outstanding 2

  def busy?(%{configuration: %{history_mode: :host_settled}} = state, origin, correlation) do
    outstanding = state.outstanding

    map_size(outstanding) >= @maximum_outstanding or Map.has_key?(outstanding, correlation) or
      (map_size(outstanding) > 0 and not overlap_allowed?(state, origin))
  end

  def busy?(_state, _origin, _correlation), do: false

  # Only modern structured completions may overlap earlier audio. Unrelated
  # ordinary requests and legacy sessions keep the original single-outstanding gate.
  defp overlap_allowed?(
         %{configuration: %{history_mode: :host_settled, reply_protocol: :mode_message_v1}},
         :tool_result
       ),
       do: true

  defp overlap_allowed?(_state, _origin), do: false

  def open(state, correlation, replay) when is_map(correlation) do
    cond do
      Map.has_key?(state.outstanding, correlation) ->
        # Distinct admissions must not overwrite each other's pending replay.
        # Completion results update replay through put_replay/3 only.
        {:error, :busy}

      map_size(state.outstanding) >= @maximum_outstanding ->
        {:error, :busy}

      true ->
        entry = %{correlation: correlation, replay: replay}

        {:ok,
         %{
           state
           | outstanding: Map.put(state.outstanding, correlation, entry)
         }}
    end
  end

  def put_replay(state, correlation, replay) when is_map(correlation) do
    case Map.fetch(state.outstanding, correlation) do
      {:ok, entry} ->
        %{state | outstanding: Map.put(state.outstanding, correlation, %{entry | replay: replay})}

      :error ->
        state
    end
  end

  def delete(state, correlation),
    do: %{state | outstanding: Map.delete(state.outstanding, correlation)}
end
