defmodule Vxpipe.Calls.PublicationWindow do
  @moduledoc "Decides when settled or deadline-bound call details are publishable."

  alias Vxpipe.Calls.{PublicationComponent, PublicationDecision}

  @default_window_seconds 60

  @spec evaluate(DateTime.t(), DateTime.t(), [PublicationComponent.t()], keyword()) ::
          {:ok, PublicationDecision.t()} | {:error, :invalid_publication_window}
  def evaluate(ended_at, assessed_at, components, options \\ [])

  def evaluate(%DateTime{} = ended_at, %DateTime{} = assessed_at, components, options)
      when is_list(components) and is_list(options) do
    with {:ok, options} <- Keyword.validate(options, window_seconds: @default_window_seconds),
         window_seconds when is_integer(window_seconds) and window_seconds >= 0 <-
           Keyword.fetch!(options, :window_seconds),
         comparison when comparison in [:lt, :eq] <- DateTime.compare(ended_at, assessed_at),
         :ok <- validate_components(components) do
      deadline = DateTime.add(ended_at, window_seconds, :second)
      pending = component_names(components, &(not PublicationComponent.settled?(&1)))
      incomplete = component_names(components, &PublicationComponent.incomplete?/1)

      {:ok,
       %PublicationDecision{
         action: action(pending, assessed_at, deadline),
         completeness: completeness(incomplete),
         ended_at: ended_at,
         deadline: deadline,
         assessed_at: assessed_at,
         components: Enum.sort_by(components, & &1.name),
         pending_components: pending,
         incomplete_components: incomplete
       }}
    else
      _invalid -> {:error, :invalid_publication_window}
    end
  end

  def evaluate(_ended_at, _assessed_at, _components, _options),
    do: {:error, :invalid_publication_window}

  defp validate_components(components) do
    names =
      Enum.map(components, fn
        %PublicationComponent{name: name} -> name
        _invalid -> nil
      end)

    if nil not in names and length(names) == MapSet.size(MapSet.new(names)),
      do: :ok,
      else: {:error, :invalid_components}
  end

  defp component_names(components, predicate) do
    components
    |> Enum.filter(predicate)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp action([], _assessed_at, _deadline), do: :publish

  defp action(_pending, assessed_at, deadline) do
    if DateTime.compare(assessed_at, deadline) == :lt, do: :wait, else: :publish
  end

  defp completeness([]), do: :complete
  defp completeness(_incomplete), do: :incomplete
end
