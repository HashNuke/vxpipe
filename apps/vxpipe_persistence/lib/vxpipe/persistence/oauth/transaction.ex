defmodule Vxpipe.Persistence.OAuth.Transaction do
  @moduledoc false
  alias Vxpipe.Persistence.Repo
  @private [log: false, telemetry_event: nil]

  def options, do: @private
  def digest(raw), do: :crypto.hash(:sha256, raw)
  def random, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  def now, do: DateTime.utc_now()
  def future?(time), do: DateTime.compare(time, now()) == :gt

  def run(operation) do
    Repo.transaction(
      fn ->
        Repo.query!("SET LOCAL lock_timeout = '2s'", [], @private)
        Repo.query!("SET LOCAL statement_timeout = '5s'", [], @private)

        case operation.() do
          {:ok, result} -> result
          :ok -> :ok
          {:commit_error, error} -> {:committed_error, error}
          {:error, error} -> Repo.rollback(error)
        end
      end,
      @private ++ [timeout: 10_000]
    )
    |> case do
      {:ok, {:committed_error, error}} -> {:error, error}
      {:ok, :ok} -> :ok
      result -> result
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
