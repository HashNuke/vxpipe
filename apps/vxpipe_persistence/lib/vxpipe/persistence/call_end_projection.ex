defmodule Vxpipe.Persistence.CallEndProjection do
  @moduledoc false

  alias Vxpipe.Calls.CallFact
  alias Vxpipe.Persistence.Schema.Call

  @spec apply(module(), Call.t(), CallFact.t()) :: {:ok, Call.t()} | {:error, atom()}
  def apply(_repo, %Call{} = call, %CallFact{kind: kind})
      when kind != :archive_stream_closed,
      do: {:ok, call}

  def apply(
        repo,
        %Call{state: :running, started_at: %DateTime{}} = call,
        %CallFact{kind: :archive_stream_closed, occurred_at: %DateTime{} = ended_at}
      ) do
    if DateTime.compare(ended_at, call.started_at) in [:eq, :gt] do
      ended_at = microsecond_precision(ended_at)

      call
      |> Call.end_changeset(ended_at)
      |> repo.update()
      |> normalize_update()
    else
      {:error, :call_end_conflict}
    end
  end

  def apply(
        _repo,
        %Call{state: :ended, ended_at: %DateTime{} = ended_at} = call,
        %CallFact{kind: :archive_stream_closed, occurred_at: %DateTime{} = occurred_at}
      ) do
    if DateTime.compare(ended_at, occurred_at) == :eq,
      do: {:ok, call},
      else: {:error, :call_end_conflict}
  end

  def apply(_repo, %Call{state: :failed} = call, %CallFact{kind: :archive_stream_closed}) do
    case Vxpipe.Persistence.ResolvedPlanCodec.decode(call.resolved_plan) do
      {:ok, %{direction: :outgoing}} -> {:ok, call}
      _other -> {:error, :call_not_running}
    end
  end

  def apply(_repo, %Call{}, %CallFact{kind: :archive_stream_closed}),
    do: {:error, :call_not_running}

  defp microsecond_precision(%DateTime{microsecond: {value, _precision}} = datetime) do
    %{datetime | microsecond: {value, 6}}
  end

  defp normalize_update({:ok, %Call{} = call}), do: {:ok, call}
  defp normalize_update({:error, _changeset}), do: {:error, :call_end_projection_failed}
end
