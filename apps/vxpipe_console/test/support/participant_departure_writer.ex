defmodule Vxpipe.Console.Test.ParticipantDepartureWriter do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Archive.Writer

  @impl true
  def write(observer, record) do
    case Vxpipe.Calls.EngineArchiveProjection.project(record) do
      {:ok, %Vxpipe.Calls.CallFact{kind: :participant_left} = fact} ->
        send(
          observer,
          {:participant_departed, fact.tenant_key, fact.call_id, fact.incarnation_id,
           fact.participant_id}
        )

      _ ->
        :ok
    end

    :ok
  end
end
