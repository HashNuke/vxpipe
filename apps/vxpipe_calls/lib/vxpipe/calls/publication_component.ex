defmodule Vxpipe.Calls.PublicationComponent do
  @moduledoc "One call-details section's settlement and completeness state."

  @statuses [:complete, :pending, :failed, :missing, :prohibited, :unconfigured, :not_produced]

  @derive {Inspect, except: [:details]}
  @enforce_keys [:name, :status, :details]
  defstruct @enforce_keys

  @type status ::
          :complete
          | :pending
          | :failed
          | :missing
          | :prohibited
          | :unconfigured
          | :not_produced

  @type t :: %__MODULE__{name: String.t(), status: status(), details: map()}

  @spec new(String.t(), status(), map()) :: {:ok, t()} | {:error, :invalid_component}
  def new(name, status, details \\ %{})

  def new(name, status, details)
      when is_binary(name) and status in @statuses and is_map(details) do
    with true <- name != "" and byte_size(name) <= 128,
         {:ok, canonical_details} <- canonical_json(details) do
      {:ok, %__MODULE__{name: name, status: status, details: canonical_details}}
    else
      _invalid -> {:error, :invalid_component}
    end
  end

  def new(_name, _status, _details), do: {:error, :invalid_component}

  @spec settled?(t()) :: boolean()
  def settled?(%__MODULE__{status: status}), do: status != :pending

  @spec incomplete?(t()) :: boolean()
  def incomplete?(%__MODULE__{status: status}), do: status in [:pending, :failed, :missing]

  @spec document(t()) :: map()
  def document(%__MODULE__{} = component) do
    %{"status" => Atom.to_string(component.status)}
    |> maybe_put_details(component.details)
  end

  defp maybe_put_details(document, details) when map_size(details) == 0, do: document
  defp maybe_put_details(document, details), do: Map.put(document, "details", details)

  defp canonical_json(value) do
    {:ok, value |> JSON.encode!() |> JSON.decode!()}
  rescue
    _error -> {:error, :not_json_safe}
  end
end
