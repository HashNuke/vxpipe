defmodule Vxpipe.Persistence.CallEndProjection do
  @moduledoc false

  import Ecto.Query
  alias Vxpipe.Calls.CallFact
  alias Vxpipe.Persistence.Schema.CallFact, as: StoredFact
  alias Vxpipe.Persistence.Schema.Call

  @spec apply(module(), Call.t(), CallFact.t()) :: {:ok, Call.t()} | {:error, atom()}
  def apply(_repo, %Call{} = call, %CallFact{kind: kind})
      when kind != :archive_stream_closed,
      do: {:ok, call}

  def apply(
        repo,
        %Call{
          gateway_cleanup_required: true,
          gateway_cleanup_completed_at: %DateTime{},
          hangup_requested_at: %DateTime{},
          state: state
        } = call,
        %CallFact{kind: :archive_stream_closed, occurred_at: occurred}
      )
      when state != :ended do
    if DateTime.compare(occurred, call.started_at || call.created_at) != :lt do
      call |> Call.cleanup_cancellation_changeset() |> repo.update() |> normalize_update()
    else
      {:error, :call_end_conflict}
    end
  end

  def apply(
        _repo,
        %Call{
          gateway_cleanup_required: true,
          gateway_cleanup_completed_at: %DateTime{},
          state: :ended,
          terminal_reason: :api_hangup
        } = call,
        %CallFact{kind: :archive_stream_closed, occurred_at: occurred}
      ) do
    if DateTime.compare(occurred, call.started_at || call.created_at) != :lt,
      do: {:ok, call},
      else: {:error, :call_end_conflict}
  end

  def apply(
        repo,
        %Call{
          gateway_cleanup_required: true,
          gateway_cleanup_completed_at: %DateTime{},
          state: :admitting,
          started_at: nil
        } = call,
        %CallFact{kind: :archive_stream_closed, occurred_at: occurred}
      ) do
    if DateTime.compare(occurred, call.created_at) != :lt and
         consistent_close?(repo, call, occurred) do
      call
      |> Call.end_changeset(microsecond_precision(occurred))
      |> repo.update()
      |> normalize_update()
    else
      {:error, :call_end_conflict}
    end
  end

  def apply(
        repo,
        %Call{
          gateway_cleanup_required: true,
          gateway_cleanup_completed_at: nil,
          state: state,
          started_at: nil,
          hangup_requested_at: requested
        } = call,
        %CallFact{kind: :archive_stream_closed, occurred_at: occurred}
      )
      when state == :admitting or (state == :failed and not is_nil(requested)) do
    if DateTime.compare(occurred, call.created_at) in [:eq, :gt] and
         consistent_close?(repo, call, occurred),
       do: {:ok, call},
       else: {:error, :call_end_conflict}
  end

  def apply(
        repo,
        %Call{state: :running, started_at: %DateTime{}} = call,
        %CallFact{kind: :archive_stream_closed, occurred_at: %DateTime{} = ended_at}
      ) do
    if DateTime.compare(ended_at, call.started_at) in [:eq, :gt] and
         consistent_close?(repo, call, ended_at) do
      if call.gateway_cleanup_required and is_nil(call.gateway_cleanup_completed_at) do
        {:ok, call}
      else
        call
        |> Call.end_changeset(microsecond_precision(ended_at))
        |> repo.update()
        |> normalize_update()
      end
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

  defp consistent_close?(repo, call, occurred) do
    occurred = microsecond_precision(occurred)

    not repo.exists?(
      from(fact in StoredFact,
        where:
          fact.call_id == ^call.id and fact.incarnation_id == ^call.incarnation_id and
            fact.kind == "archive_stream_closed" and fact.occurred_at != ^occurred
      )
    )
  end

  defp microsecond_precision(%DateTime{microsecond: {value, _precision}} = datetime) do
    %{datetime | microsecond: {value, 6}}
  end

  defp normalize_update({:ok, %Call{} = call}), do: {:ok, call}
  defp normalize_update({:error, _changeset}), do: {:error, :call_end_projection_failed}
end
