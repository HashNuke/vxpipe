defmodule Vxpipe.CallEngine.Readiness.Resource do
  @moduledoc false

  @enforce_keys [
    :kind,
    :scope,
    :instance,
    :generation,
    :configuration,
    :policy_interval,
    :adapter
  ]
  defstruct @enforce_keys ++ [binding: nil]

  @type scope :: :room | {:participant, String.t()}
  @type key :: {atom(), scope(), term()}
  @type t :: %__MODULE__{
          kind: atom(),
          scope: scope(),
          binding: term(),
          instance: pid() | nil,
          generation: reference() | nil,
          configuration: binary(),
          policy_interval: term(),
          adapter: module() | nil
        }

  @spec key(t()) :: key()
  def key(%__MODULE__{} = resource), do: {resource.kind, resource.scope, resource.binding}

  @spec new(atom(), scope(), module(), term(), keyword()) :: t()
  def new(kind, scope, adapter, configuration, options \\ []) do
    %__MODULE__{
      kind: kind,
      scope: scope,
      binding: Keyword.get(options, :binding),
      instance: self(),
      generation: make_ref(),
      configuration: signature(configuration),
      policy_interval: nil,
      adapter: adapter
    }
  end

  # Keep configuration (including private provider options) out of readiness reports.
  @spec signature(term()) :: binary()
  def signature(configuration) do
    :crypto.hash(:sha256, :erlang.term_to_binary(configuration, [:deterministic]))
  end

  @spec bound?(t()) :: boolean()
  def bound?(%__MODULE__{} = resource) do
    is_pid(resource.instance) and is_reference(resource.generation) and resource.adapter != nil
  end
end
