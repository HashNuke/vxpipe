defmodule Vxpipe.Persistence.OutgoingLifecycleProjection do
  @moduledoc false
  alias Vxpipe.Calls.OutgoingCallFact
  alias Vxpipe.Persistence.ResolvedPlanCodec

  def apply(repo, call, fact) do
    if OutgoingCallFact.kind?(fact.kind) or fact.kind == :archive_stream_closed do
      case ResolvedPlanCodec.decode(call.resolved_plan) do
        {:ok, %{direction: :outgoing}} ->
          project(repo, call, fact)

        _other ->
          if OutgoingCallFact.kind?(fact.kind),
            do: {:error, :outgoing_lifecycle_conflict},
            else: {:ok, call}
      end
    else
      {:ok, call}
    end
  end

  defp project(repo, call, fact) do
    with :ok <- after_start(call, fact.occurred_at),
         {:ok, changes} <- changes(call, fact) do
      call
      |> Ecto.Changeset.change(changes)
      |> Ecto.Changeset.check_constraint(:dial_submitted_at, name: :calls_outgoing_times)
      |> repo.update()
      |> normalize_update()
    else
      _invalid -> {:error, :outgoing_lifecycle_conflict}
    end
  end

  defp normalize_update({:ok, call}), do: {:ok, call}
  defp normalize_update({:error, _changeset}), do: {:error, :outgoing_lifecycle_conflict}

  defp after_start(%{started_at: %DateTime{} = started}, occurred) do
    if DateTime.compare(occurred, started) in [:eq, :gt], do: :ok, else: :error
  end

  defp after_start(_call, _occurred), do: :error

  defp changes(call, %{kind: :outgoing_dial_submitted, occurred_at: time}) do
    if call.dial_submitted_at == nil, do: {:ok, [dial_submitted_at: time]}, else: {:ok, []}
  end

  defp changes(call, %{kind: :outgoing_call_answered, occurred_at: time}) do
    cond do
      call.outgoing_outcome != nil ->
        {:ok, []}

      ordered?(call.dial_submitted_at, time) ->
        {:ok, [outgoing_outcome: :answered, answered_at: time]}

      true ->
        {:error, :outgoing_lifecycle_conflict}
    end
  end

  defp changes(call, %{kind: :outgoing_dial_ended, occurred_at: time, payload: payload}) do
    cond do
      call.dial_ended_at != nil ->
        {:ok, []}

      not ordered?(call.answered_at || call.dial_submitted_at, time) ->
        {:error, :outgoing_lifecycle_conflict}

      true ->
        {:ok,
         [
           outgoing_outcome: call.outgoing_outcome || OutgoingCallFact.outcome(payload),
           dial_ended_at: time
         ]}
    end
  end

  defp changes(call, %{kind: :archive_stream_closed, occurred_at: time, payload: payload}) do
    cond do
      call.dial_ended_at != nil ->
        {:ok, []}

      call.dial_submitted_at == nil ->
        {:ok, [outgoing_outcome: call.outgoing_outcome || preparation_outcome(payload)]}

      ordered?(call.answered_at || call.dial_submitted_at, time) ->
        {:ok, [outgoing_outcome: closure_outcome(call, payload), dial_ended_at: time]}

      true ->
        {:error, :outgoing_lifecycle_conflict}
    end
  end

  defp closure_outcome(call, payload) do
    call.outgoing_outcome || source_outcome(payload) || :unknown
  end

  defp source_outcome(%{"source_reason" => ["shutdown", ["outgoing_call", name]]}) do
    case OutgoingCallFact.validate(:outgoing_dial_ended, %{"outcome" => name}) do
      :ok -> OutgoingCallFact.outcome(%{"outcome" => name})
      _invalid -> nil
    end
  end

  defp source_outcome(_payload), do: nil

  defp preparation_outcome(%{"source_reason" => reason})
       when reason in ["startup_unavailable", "opening_audio_unavailable"], do: :failed

  defp preparation_outcome(payload), do: source_outcome(payload) || :unknown

  defp ordered?(%DateTime{} = before, after_time),
    do: DateTime.compare(before, after_time) in [:lt, :eq]

  defp ordered?(_missing, _time), do: false
end
