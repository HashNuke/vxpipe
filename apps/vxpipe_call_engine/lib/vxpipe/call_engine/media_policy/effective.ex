defmodule Vxpipe.CallEngine.MediaPolicy.Effective do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy

  @enforce_keys [:audio_routes, :transcript_routes, :record_audio, :save_transcripts]
  defstruct @enforce_keys

  @type routes :: :unrestricted | %{String.t() => MapSet.t(String.t())}

  @type t :: %__MODULE__{
          audio_routes: routes(),
          transcript_routes: routes(),
          record_audio: boolean(),
          save_transcripts: boolean()
        }

  @spec compose(MediaPolicy.t(), MediaPolicy.t(), %{String.t() => MediaPolicy.t()}) ::
          {:ok, t()} | {:error, :invalid_policy}
  def compose(%MediaPolicy{} = host_ceiling, %MediaPolicy{} = normal_policy, contributions)
      when is_map(contributions) do
    policies = [host_ceiling, normal_policy | Map.values(contributions)]

    if valid_contributions?(contributions) and Enum.all?(policies, &MediaPolicy.valid?/1) do
      {:ok,
       %__MODULE__{
         audio_routes: compose_routes(Enum.map(policies, & &1.audio_routes)),
         transcript_routes: compose_routes(Enum.map(policies, & &1.transcript_routes)),
         record_audio: permission_granted?(Enum.map(policies, & &1.record_audio)),
         save_transcripts: permission_granted?(Enum.map(policies, & &1.save_transcripts))
       }}
    else
      {:error, :invalid_policy}
    end
  end

  def compose(_host_ceiling, _normal_policy, _contributions), do: {:error, :invalid_policy}

  @spec audio_route_permitted?(t(), String.t(), String.t()) :: boolean()
  def audio_route_permitted?(%__MODULE__{audio_routes: routes}, source_id, recipient_id) do
    route_permitted?(routes, source_id, recipient_id)
  end

  @spec transcript_route_permitted?(t(), String.t(), String.t()) :: boolean()
  def transcript_route_permitted?(
        %__MODULE__{transcript_routes: routes},
        source_id,
        recipient_id
      ) do
    route_permitted?(routes, source_id, recipient_id)
  end

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = policy) do
    valid_routes?(policy.audio_routes) and valid_routes?(policy.transcript_routes) and
      is_boolean(policy.record_audio) and is_boolean(policy.save_transcripts)
  end

  def valid?(_policy), do: false

  defp compose_routes(routes) do
    case Enum.reject(routes, &(&1 == :inherit)) do
      [] -> :unrestricted
      [routes | restrictions] -> Enum.reduce(restrictions, routes, &intersect_routes/2)
    end
  end

  defp intersect_routes(restriction, current) do
    Enum.reduce(current, %{}, fn {source_id, current_recipients}, intersection ->
      case Map.fetch(restriction, source_id) do
        {:ok, restricted_recipients} ->
          Map.put(
            intersection,
            source_id,
            MapSet.intersection(current_recipients, restricted_recipients)
          )

        :error ->
          intersection
      end
    end)
  end

  defp permission_granted?(permissions), do: Enum.all?(permissions, &(&1 != false))

  defp route_permitted?(:unrestricted, source_id, recipient_id),
    do: is_binary(source_id) and is_binary(recipient_id)

  defp route_permitted?(routes, source_id, recipient_id)
       when is_map(routes) and is_binary(source_id) and is_binary(recipient_id) do
    case Map.fetch(routes, source_id) do
      {:ok, recipients} -> MapSet.member?(recipients, recipient_id)
      :error -> false
    end
  end

  defp route_permitted?(_routes, _source_id, _recipient_id), do: false

  defp valid_routes?(:unrestricted), do: true

  defp valid_routes?(routes) when is_map(routes) do
    Enum.all?(routes, fn {source_id, recipients} ->
      is_binary(source_id) and is_struct(recipients, MapSet) and
        Enum.all?(recipients, &is_binary/1)
    end)
  end

  defp valid_routes?(_routes), do: false

  defp valid_contributions?(contributions) do
    Enum.all?(contributions, fn {owner_id, policy} ->
      is_binary(owner_id) and match?(%MediaPolicy{}, policy)
    end)
  end
end
