defmodule Vxpipe.AgentRuntime.Readiness do
  @moduledoc "Initialization evidence for one installed agent conversation."

  alias Vxpipe.AgentRuntime.SessionConfiguration

  @enforce_keys [:instance, :generation, :configuration]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          instance: pid(),
          generation: reference(),
          configuration: binary()
        }
  @type status :: :preparing | :ready | :failed

  @doc false
  @spec new(SessionConfiguration.t()) :: t()
  def new(%SessionConfiguration{} = configuration) do
    %__MODULE__{
      instance: self(),
      generation: make_ref(),
      configuration: :crypto.hash(:sha256, :erlang.term_to_binary(configuration, [:deterministic]))
    }
  end

  @doc false
  @spec status(SessionConfiguration.t(), :idle | :busy) :: status()
  def status(%SessionConfiguration{model_provider: provider, model: model}, session_status) do
    case provider_status(provider, model) do
      :ready when session_status == :idle -> :ready
      :ready -> :preparing
      other -> other
    end
  end

  defp provider_status(provider, model) do
    if function_exported?(provider, :readiness, 1) do
      case provider.readiness(model) do
        status when status in [:preparing, :ready, :failed] -> status
        _unsupported -> :failed
      end
    else
      :failed
    end
  rescue
    _exception -> :failed
  catch
    _kind, _reason -> :failed
  end
end
