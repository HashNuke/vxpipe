defmodule Vxpipe.Calls.LatencyRepository do
  @moduledoc "Separate durable diagnostics port; never part of immutable publication completion."
  alias Vxpipe.Calls.{LatencyRun, TurnDiagnostic}
  @callback put_run(term(), %LatencyRun{}) :: {:ok, %LatencyRun{}} | {:error, atom()}
  @callback put_turn(term(), String.t(), String.t(), String.t(), %TurnDiagnostic{}) ::
              {:ok, %TurnDiagnostic{}} | {:error, atom()}
  @callback fetch_run(term(), String.t(), String.t(), String.t()) ::
              {:ok, %LatencyRun{}} | {:error, atom()}
  @callback list_turns(
              term(),
              String.t(),
              String.t(),
              String.t(),
              pos_integer(),
              String.t() | nil
            ) ::
              {:ok, [%TurnDiagnostic{}]} | {:error, atom()}
  @callback summarize(term(), String.t(), String.t()) :: {:ok, [map()]} | {:error, atom()}
  @callback list_runs(term(), String.t(), String.t(), pos_integer(), String.t() | nil) ::
              {:ok, %{entries: [map()], next_cursor: String.t() | nil}} | {:error, atom()}
end
