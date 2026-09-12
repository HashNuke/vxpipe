defmodule Vxpipe.Calls.CallDetailsSource do
  @moduledoc "A permitted persisted-fact projection used to construct call details."

  @fields [:call, :participants, :transcript, :tools, :transfers, :usage, :variables, :artifacts]
  @list_fields [:participants, :transcript, :tools, :transfers, :artifacts]
  @map_fields [:call, :usage, :variables]
  @identity_fields [
    "call_id",
    "tenant_key",
    "definition_id",
    "definition_revision",
    "definition_schema_version",
    "plan_digest"
  ]
  @lifecycle_fields [
    "state",
    "direction",
    "route",
    "created_at",
    "started_at",
    "ended_at",
    "terminal_reason"
  ]

  @derive {Inspect, except: @fields}
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_call_details_source}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <- Keyword.validate(attributes, @fields),
         true <- Enum.all?(@fields, &Keyword.has_key?(attributes, &1)),
         true <- Enum.all?(@list_fields, &(attributes |> Keyword.fetch!(&1) |> is_list())),
         true <- Enum.all?(@map_fields, &(attributes |> Keyword.fetch!(&1) |> is_map())),
         {:ok, attributes} <- canonicalize(attributes),
         :ok <- validate_call(Keyword.fetch!(attributes, :call)) do
      {:ok, struct!(__MODULE__, attributes)}
    else
      _invalid -> {:error, :invalid_call_details_source}
    end
  end

  def new(_attributes), do: {:error, :invalid_call_details_source}

  @spec document(t()) :: map()
  def document(%__MODULE__{} = source) do
    %{
      "call" => source.call,
      "participants" => source.participants,
      "transcript" => source.transcript,
      "tools" => source.tools,
      "transfers" => source.transfers,
      "usage" => source.usage,
      "variables" => source.variables,
      "artifacts" => source.artifacts
    }
  end

  defp canonicalize(attributes) do
    {:ok,
     Enum.map(attributes, fn {field, value} ->
       {field, value |> JSON.encode!() |> JSON.decode!()}
     end)}
  rescue
    _error -> {:error, :not_json_safe}
  end

  defp validate_call(%{"identity" => identity, "lifecycle" => lifecycle})
       when is_map(identity) and is_map(lifecycle) do
    if present?(identity, @identity_fields) and present?(lifecycle, @lifecycle_fields),
      do: :ok,
      else: {:error, :missing_call_details}
  end

  defp validate_call(_call), do: {:error, :missing_call_details}

  defp present?(map, fields), do: Enum.all?(fields, &Map.has_key?(map, &1))
end
