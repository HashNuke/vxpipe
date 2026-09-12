defmodule Vxpipe.Calls.CallDetailsAssessment do
  @moduledoc "Permitted persisted source facts and component state assessed after one call ends."

  alias Vxpipe.Calls.{CallDetailsSource, PublicationComponent}

  @derive {Inspect, except: [:source, :components]}
  @enforce_keys [:ended_at, :source, :components]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          ended_at: DateTime.t(),
          source: CallDetailsSource.t(),
          components: [PublicationComponent.t()]
        }

  @spec new(DateTime.t(), CallDetailsSource.t(), [PublicationComponent.t()]) ::
          {:ok, t()} | {:error, :invalid_call_details_assessment}
  def new(%DateTime{} = ended_at, %CallDetailsSource{} = source, components)
      when is_list(components) do
    if utc?(ended_at) and Enum.all?(components, &is_struct(&1, PublicationComponent)) do
      {:ok, %__MODULE__{ended_at: ended_at, source: source, components: components}}
    else
      {:error, :invalid_call_details_assessment}
    end
  end

  def new(_ended_at, _source, _components), do: {:error, :invalid_call_details_assessment}

  defp utc?(value), do: value.utc_offset == 0 and value.std_offset == 0
end
