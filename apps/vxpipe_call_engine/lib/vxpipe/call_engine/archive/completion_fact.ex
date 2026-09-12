defmodule Vxpipe.CallEngine.Archive.CompletionFact do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.Id

  @spec build(map(), map(), term(), DateTime.t()) :: Fact.t()
  def build(context, stats, source_reason, %DateTime{} = source_stopped_at) do
    Fact.new!(
      id: Id.generate(:event),
      kind: :archive_stream_closed,
      sequence: context.maximum_sequence + 1,
      tenant_id: context.tenant_id,
      call_id: context.call_id,
      room_id: context.room_id,
      incarnation_id: context.incarnation_id,
      occurred_at: source_stopped_at,
      source_policy: context.source_policy,
      payload: %{
        "accepted" => stats.accepted,
        "discarded" => stats.discarded,
        "incomplete" => stats.incomplete?,
        "overflow" => stats.overflow,
        "retries" => stats.retries,
        "source_reason" => source_reason,
        "unavailable" => stats.unavailable
      }
    )
  end
end
