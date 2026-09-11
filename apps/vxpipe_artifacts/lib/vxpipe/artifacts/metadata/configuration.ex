defmodule Vxpipe.Artifacts.Metadata.Configuration do
  @moduledoc false

  alias Vxpipe.Artifacts.Metadata.Writer

  @default_maximum_attempts 5
  @default_retry_delay_ms 250
  @default_write_timeout_ms 5_000

  @enforce_keys [
    :writer,
    :writer_options,
    :maximum_attempts,
    :retry_delay_ms,
    :write_timeout_ms
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          writer: module(),
          writer_options: keyword(),
          maximum_attempts: pos_integer(),
          retry_delay_ms: non_neg_integer(),
          write_timeout_ms: pos_integer()
        }

  @spec new(nil | keyword()) :: {:ok, nil | t()} | {:error, :invalid_metadata_configuration}
  def new(nil), do: {:ok, nil}

  def new(options) when is_list(options) do
    with {writer, writer_options} when is_atom(writer) and is_list(writer_options) <-
           Keyword.get(options, :writer),
         true <- Writer.valid?(writer),
         maximum_attempts when is_integer(maximum_attempts) and maximum_attempts > 0 <-
           Keyword.get(options, :maximum_attempts, @default_maximum_attempts),
         retry_delay_ms when is_integer(retry_delay_ms) and retry_delay_ms >= 0 <-
           Keyword.get(options, :retry_delay_ms, @default_retry_delay_ms),
         write_timeout_ms when is_integer(write_timeout_ms) and write_timeout_ms > 0 <-
           Keyword.get(options, :write_timeout_ms, @default_write_timeout_ms) do
      {:ok,
       %__MODULE__{
         writer: writer,
         writer_options: writer_options,
         maximum_attempts: maximum_attempts,
         retry_delay_ms: retry_delay_ms,
         write_timeout_ms: write_timeout_ms
       }}
    else
      _invalid -> {:error, :invalid_metadata_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_metadata_configuration}
end
