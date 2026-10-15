defmodule Vxpipe.Persistence.CallIncarnationBinding do
  @moduledoc "Immutable incarnation checks for callers already holding the call-row lock."

  import Ecto.Query

  alias Vxpipe.Persistence.Schema.{Call, CallFact, VariableSnapshot}

  def bind(
        _repo,
        %Call{incarnation_id: incarnation, incarnation_binding_verified: true} = call,
        incarnation
      ),
      do: {:ok, call}

  def bind(repo, %Call{} = call, incarnation) do
    with :ok <- matching_incarnation(call, incarnation),
         :ok <- matching_history(repo, call, incarnation) do
      repo.update(
        Ecto.Changeset.change(call,
          incarnation_id: incarnation,
          incarnation_binding_verified: true
        )
      )
    end
  end

  defp matching_incarnation(%Call{incarnation_id: nil}, _incarnation), do: :ok
  defp matching_incarnation(%Call{incarnation_id: incarnation}, incarnation), do: :ok
  defp matching_incarnation(%Call{}, _incarnation), do: {:error, :call_incarnation_mismatch}

  defp matching_history(repo, call, incarnation) do
    conflict? =
      Enum.any?([CallFact, VariableSnapshot], fn schema ->
        repo.exists?(
          from(record in schema,
            where: record.call_id == ^call.id,
            where: record.incarnation_id != ^incarnation or record.room_id != ^call.room_id
          )
        )
      end)

    if conflict?, do: {:error, :call_incarnation_mismatch}, else: :ok
  end

  def allow_start(%Call{hangup_requested_at: %DateTime{}}, _incarnation),
    do: {:error, :call_unavailable}

  def allow_start(%Call{incarnation_id: nil}, _incarnation), do: :ok
  def allow_start(%Call{incarnation_id: incarnation}, incarnation), do: :ok
  def allow_start(%Call{}, _incarnation), do: {:error, :call_incarnation_mismatch}
end
