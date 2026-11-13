defmodule Vxpipe.CallEngine.VoiceCatalog do
  @moduledoc "On-demand authoring catalogs. Callers must resolve and authorize credentials first."
  alias Vxpipe.CallEngine.ModelCatalog
  alias Vxpipe.CallEngine.VoiceCatalog.Query
  alias Vxpipe.Providers.ElevenLabs.Voices

  def describe(scope) do
    with {:ok, model, adapter} <- resolve(scope) do
      {:ok,
       %{
         providerName: ModelCatalog.provider_name(scope.provider),
         modelName: model.name,
         search: true,
         filters: filters(adapter)
       }}
    end
  end

  def list(scope, query, payload, options \\ []) do
    with {:ok, model, adapter} <- resolve(scope),
         {:ok, query} <- Query.parse(query, filters(adapter)) do
      case adapter do
        :finite ->
          Query.page(
            Enum.map(model.voices.values, &Map.put(Map.take(&1, [:id, :name]), :attributes, [])),
            query
          )

        adapter ->
          adapter.list(scope, query, payload, options)
      end
    end
  end

  def get(scope, id, payload, options \\ []) do
    with {:ok, model, adapter} <- resolve(scope),
         true <- Query.valid_id?(id) do
      case adapter do
        :finite ->
          {:ok,
           Enum.find_value(model.voices.values, fn voice ->
             if voice.id == id, do: Map.put(Map.take(voice, [:id, :name]), :attributes, [])
           end)}

        adapter ->
          adapter.get(scope, id, payload, options)
      end
    else
      false -> {:error, :invalid_voice_query}
      error -> error
    end
  end

  defp resolve(%{provider: provider, capability: capability, model: id})
       when is_binary(provider) and is_binary(id) and
              capability in ["text_to_speech", "speech_to_speech"] do
    with {:ok, models} <- ModelCatalog.models(provider, capability),
         %{} = model <- Enum.find(models, &(&1.id == id)),
         {:ok, adapter} <- adapter(provider, capability, model) do
      {:ok, model, adapter}
    else
      _ -> {:error, :invalid_voice_scope}
    end
  end

  defp resolve(_), do: {:error, :invalid_voice_scope}
  defp adapter(_, _, %{voices: %{type: :list}}), do: {:ok, :finite}
  defp adapter("elevenlabs", "text_to_speech", _), do: {:ok, Voices}
  defp adapter(_, _, _), do: {:error, :invalid_voice_scope}
  defp filters(:finite), do: []
  defp filters(adapter), do: adapter.filters()
end
