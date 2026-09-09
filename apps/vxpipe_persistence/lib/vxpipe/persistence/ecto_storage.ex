defmodule Vxpipe.Persistence.EctoStorage do
  @moduledoc "Projects private engine archive facts through Calls-owned workflows."

  @behaviour Vxpipe.CallEngine.Archive.Writer

  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.Archive.Fact, as: EngineFact
  alias Vxpipe.Calls
  alias Vxpipe.Calls.EngineArchiveProjection

  @terminal_errors [
    :call_incarnation_mismatch,
    :call_fact_conflict,
    :call_fact_insert_failed,
    :call_fact_sequence_conflict,
    :call_not_found,
    :call_not_started,
    :invalid_variable_snapshot,
    :invalid_call_fact,
    :variable_snapshot_conflict,
    :variable_snapshot_revision_conflict
  ]

  @impl true
  def write(options, %BaselineSnapshot{} = fact) when is_list(options) do
    fact
    |> EngineArchiveProjection.project()
    |> store(options)
  end

  def write(options, %UpdateSnapshot{} = fact) when is_list(options) do
    fact
    |> EngineArchiveProjection.project()
    |> store(options)
  end

  def write(options, %EngineFact{} = fact) when is_list(options) do
    fact
    |> EngineArchiveProjection.project()
    |> store_call_fact(options)
  end

  def write(_options, _unsupported), do: {:discard, :unsupported_archive_fact}

  defp store({:ok, snapshot}, options) do
    case Calls.archive_variable_snapshot(snapshot, options) do
      {:ok, _stored} -> :ok
      {:error, reason} when reason in @terminal_errors -> {:discard, reason}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp store({:error, reason}, _options), do: {:discard, reason}

  defp store_call_fact({:ok, fact}, options) do
    case Calls.archive_call_fact(fact, options) do
      {:ok, _stored} -> :ok
      {:error, reason} when reason in @terminal_errors -> {:discard, reason}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp store_call_fact({:error, reason}, _options), do: {:discard, reason}
end
