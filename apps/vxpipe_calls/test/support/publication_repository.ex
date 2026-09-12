defmodule Vxpipe.Calls.TestPublicationRepository do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationRepository

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication, CallDetailsSnapshot}

  def publications(agent), do: Agent.get(agent, & &1.publications)

  @impl true
  def reserve(agent, tenant_key, call_id, %CallDetailsSnapshot{} = snapshot) do
    caller = self()

    Agent.get_and_update(agent, fn state ->
      send(state.observer, {:publication_reserved, caller, tenant_key, call_id})

      case Map.fetch(state.publications, snapshot.source_digest) do
        {:ok, publication} ->
          {{:ok, publication, :existing}, state}

        :error ->
          {:ok, publication} = CallDetailsPublication.pending(tenant_key, call_id, snapshot)
          publications = Map.put(state.publications, snapshot.source_digest, publication)
          {{:ok, publication, :created}, %{state | publications: publications}}
      end
    end)
  end

  @impl true
  def mark_published(agent, tenant_key, call_id, publication_id, %CallDetailsObject{} = object) do
    caller = self()

    Agent.get_and_update(agent, fn state ->
      send(state.observer, {:publication_committed, caller, tenant_key, call_id, publication_id})

      with {_digest, publication} <-
             Enum.find(state.publications, fn {_digest, publication} ->
               publication.id == publication_id
             end),
           {:ok, published} <- CallDetailsPublication.publish(publication, object) do
        publications = Map.put(state.publications, published.source_digest, published)
        {{:ok, published}, %{state | publications: publications}}
      else
        nil -> {{:error, :publication_not_found}, state}
        {:error, reason} -> {{:error, reason}, state}
      end
    end)
  end

  @impl true
  def list_pending(agent, limit) do
    caller = self()

    Agent.get(agent, fn state ->
      case Map.get(state, :list_result) do
        nil ->
          pending(state, caller, limit)

        result ->
          send(state.observer, {:pending_publications_listed, caller, limit})
          result
      end
    end)
  end

  defp pending(state, caller, limit) do
    send(state.observer, {:pending_publications_listed, caller, limit})

    publications =
      state.publications
      |> Map.values()
      |> Enum.filter(&(&1.status == :pending))
      |> Enum.sort_by(&{&1.recorded_at, &1.id}, DateTime)
      |> Enum.take(limit)

    {:ok, publications}
  end
end
