defmodule Vxpipe.CallEngine.OpeningAudio.Settings do
  @moduledoc false

  alias Vxpipe.CallEngine.OpeningAudio.{AssetCache, ReqFetcher}

  @default_maximum_bytes 6_291_456
  @default_maximum_duration_ms 60_000
  @default_timeout_ms 5_000
  @fields [:cache, :fetcher, :maximum_bytes, :maximum_duration_ms, :timeout_ms]

  @derive {Inspect, only: [:cache, :maximum_bytes, :maximum_duration_ms, :timeout_ms]}
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          cache: GenServer.server(),
          fetcher: {module(), term()},
          maximum_bytes: pos_integer(),
          maximum_duration_ms: pos_integer(),
          timeout_ms: pos_integer()
        }

  @spec new(keyword() | t()) :: {:ok, t()} | {:error, :invalid_opening_audio_configuration}
  def new(%__MODULE__{} = settings), do: {:ok, settings}

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- Enum.all?(Keyword.keys(options), &(&1 in @fields)),
         {:ok, cache} <- cache(Keyword.get(options, :cache, AssetCache)),
         {fetcher, _fetcher_options} = fetcher_config <-
           Keyword.get(options, :fetcher, {ReqFetcher, []}),
         true <- fetcher?(fetcher),
         maximum_bytes when maximum_bytes in 44..16_777_216 <-
           Keyword.get(options, :maximum_bytes, @default_maximum_bytes),
         maximum_duration_ms when maximum_duration_ms in 1..300_000 <-
           Keyword.get(options, :maximum_duration_ms, @default_maximum_duration_ms),
         timeout_ms when timeout_ms in 100..30_000 <-
           Keyword.get(options, :timeout_ms, @default_timeout_ms) do
      {:ok,
       %__MODULE__{
         cache: cache,
         fetcher: fetcher_config,
         maximum_bytes: maximum_bytes,
         maximum_duration_ms: maximum_duration_ms,
         timeout_ms: timeout_ms
       }}
    else
      _invalid -> {:error, :invalid_opening_audio_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_opening_audio_configuration}

  defp cache(value) when is_pid(value) or is_atom(value), do: {:ok, value}

  defp cache(value) when is_list(value) do
    if Keyword.keyword?(value), do: {:ok, AssetCache}, else: :error
  end

  defp cache(_value), do: :error

  defp fetcher?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :fetch, 3)
  end
end
