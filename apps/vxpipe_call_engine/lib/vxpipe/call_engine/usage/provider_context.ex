defmodule Vxpipe.CallEngine.Usage.ProviderContext do
  @moduledoc """
  Namespaced provider selectors and genuine external operation identifiers.

  Request, operation, and session identifiers remain available through explicit fields but are
  omitted from ordinary inspection so logs do not become an accidental provider-data surface.
  """

  @derive {Inspect, only: [:name, :integration_id, :model, :voice]}
  @enforce_keys [:name]
  defstruct [
    :name,
    :integration_id,
    :model,
    :voice,
    :request_id,
    :operation_id,
    :session_id
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          integration_id: String.t() | nil,
          model: String.t() | nil,
          voice: String.t() | nil,
          request_id: String.t() | nil,
          operation_id: String.t() | nil,
          session_id: String.t() | nil
        }

  @fields [
    :name,
    :integration_id,
    :model,
    :voice,
    :request_id,
    :operation_id,
    :session_id
  ]

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_provider_context}
  def new(options) when is_list(options) do
    defaults = Enum.map(@fields -- [:name], &{&1, nil})

    with {:ok, options} <- Keyword.validate(options, [:name | defaults]),
         name when is_binary(name) <- Keyword.get(options, :name),
         true <- valid_value?(name),
         true <-
           Enum.all?(@fields -- [:name], fn field ->
             valid_value?(Keyword.get(options, field))
           end) do
      {:ok, struct!(__MODULE__, options)}
    else
      _invalid -> {:error, :invalid_provider_context}
    end
  end

  def new(_options), do: {:error, :invalid_provider_context}

  defp valid_value?(nil), do: true

  defp valid_value?(value) do
    is_binary(value) and String.trim(value) != "" and byte_size(value) <= 256
  end
end
