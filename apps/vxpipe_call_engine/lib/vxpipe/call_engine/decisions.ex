defmodule Vxpipe.CallEngine.Decisions do
  @moduledoc """
  Binds a saved Decisions selection for one activation and scores named questions.

  The credential source resolves the selection's credential name within its tenant
  and checks any supplied call-plan binding. Evaluation reuses that private binding.
  The caller supplies permitted evidence and applies policy thresholds to the returned
  probabilities. Pass an absolute monotonic deadline in milliseconds as `:deadline_ms`.
  """

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.{CapabilityCatalog, CredentialSource, ProviderCredential}

  @enforce_keys [:provider, :adapter, :config]
  @derive {Inspect, only: [:provider]}
  defstruct @enforce_keys

  @opaque t :: %__MODULE__{provider: String.t(), adapter: module(), config: struct()}

  @type result :: %{
          provider: String.t(),
          model: String.t() | nil,
          probabilities: %{String.t() => float()},
          usage: map() | :unknown,
          request_id: String.t() | nil,
          attempts: 1 | 2,
          elapsed_ms: non_neg_integer()
        }

  @spec bind(String.t(), CapabilitySelection.t(), keyword()) :: {:ok, t()} | {:error, atom()}
  def bind(tenant_id, %CapabilitySelection{kind: :decisions} = selection, options) do
    with {:ok, adapter} <- CapabilityCatalog.adapter(selection),
         {:ok, credential} <- CredentialSource.resolve(tenant_id, selection, options),
         {:ok, key} <- api_key(credential),
         {:ok, config} <- adapter.new(model: selection.model, api_key: key) do
      {:ok, %__MODULE__{provider: selection.provider, adapter: adapter, config: config}}
    end
  end

  def bind(_tenant_id, _selection, _options), do: {:error, :unsupported_capability}

  @doc "Returns named probabilities and the model, usage and timing reported by the selected adapter."
  @spec evaluate(t(), map() | String.t(), [map()], keyword()) ::
          {:ok, result()} | {:error, atom()}
  def evaluate(%__MODULE__{} = bound, evidence, questions, options \\ []) do
    with {:ok, result} <- bound.adapter.evaluate(bound.config, evidence, questions, options) do
      {:ok, Map.put(result, :provider, bound.provider)}
    end
  end

  defp api_key(%ProviderCredential{auth_kind: "api_key", payload: %{"api_key" => key}})
       when is_binary(key),
       do: {:ok, key}

  defp api_key(_credential), do: {:error, :provider_credential_unavailable}
end
