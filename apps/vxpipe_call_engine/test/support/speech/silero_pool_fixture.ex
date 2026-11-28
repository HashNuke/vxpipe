defmodule Vxpipe.CallEngine.Speech.SileroPoolFixture do
  @moduledoc false
  import ExUnit.Callbacks, only: [start_supervised!: 2]
  alias Vxpipe.CallEngine.Speech.Silero
  alias Silero.{Model, ModelCache, Pool, Worker}

  # Each test module gets its own real dispatcher. Only the model loader and
  # native inference call are replaced. Packed state carries a test sample index.
  def options(scope, opts) do
    pool = start_pool(scope, &classify_rows/2)

    cache =
      start_supervised!(
        {ModelCache,
         name: nil,
         load: fn ->
           with {:ok, model} <- Keyword.fetch!(opts, :load).() do
             {:ok, %Model{resource: {model, Keyword.get(opts, :classify)}, sample_rate: 16_000}}
           end
         end},
        id: make_ref()
      )

    Keyword.merge(opts, pool: pool, model_cache: cache)
  end

  def native_options(scope, loader, run) do
    pool = start_pool(scope, run)
    cache = start_supervised!({ModelCache, name: nil, load: loader}, id: make_ref())
    [pool: pool, model_cache: cache]
  end

  defp start_pool(scope, run) do
    pool = Module.concat(scope, SileroPool)

    unless Process.whereis(pool) do
      start_supervised!({Pool, name: pool, budget: %{workers: 1}}, id: pool)
      start_supervised!({Worker, {pool, run}}, id: {pool, Worker})
    end

    pool
  end

  defp classify_rows(%Model{resource: {model, classify}}, rows) do
    Enum.reduce_while(rows, {:ok, []}, fn {pcm, <<samples::64, rest::binary>>}, {:ok, results} ->
      case classify.(model, %{Silero.new() | samples: samples}, pcm) do
        {:ok, _, [p]} -> {:cont, {:ok, [{p, <<samples + 512::64, rest::binary>>} | results]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end
end
