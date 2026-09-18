defmodule Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.MediaPolicy, as: CallSpecPolicy

  @enforce_keys [:audio_routes, :transcript_routes, :record_audio, :save_transcripts]
  defstruct @enforce_keys

  @type routes :: :inherit | %{String.t() => MapSet.t(String.t())}
  @type permission :: :inherit | boolean()

  @type t :: %__MODULE__{
          audio_routes: routes(),
          transcript_routes: routes(),
          record_audio: permission(),
          save_transcripts: permission()
        }

  @spec resolve(CallSpecPolicy.t(), %{String.t() => String.t()}) :: {:ok, t()} | :error
  def resolve(%CallSpecPolicy{} = policy, participant_ids) when is_map(participant_ids) do
    with {:ok, audio_routes} <- resolve_routes(policy.audio_routes, participant_ids),
         {:ok, transcript_routes} <- resolve_routes(policy.transcript_routes, participant_ids),
         :ok <- validate_permission(policy.record_audio),
         :ok <- validate_permission(policy.save_transcripts) do
      {:ok,
       %__MODULE__{
         audio_routes: audio_routes,
         transcript_routes: transcript_routes,
         record_audio: policy.record_audio,
         save_transcripts: policy.save_transcripts
       }}
    end
  end

  def resolve(_policy, _participant_ids), do: :error

  @spec inherit() :: t()
  def inherit do
    %__MODULE__{
      audio_routes: :inherit,
      transcript_routes: :inherit,
      record_audio: :inherit,
      save_transcripts: :inherit
    }
  end

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = policy) do
    valid_routes?(policy.audio_routes) and
      valid_routes?(policy.transcript_routes) and
      validate_permission(policy.record_audio) == :ok and
      validate_permission(policy.save_transcripts) == :ok
  end

  def valid?(_policy), do: false

  defp resolve_routes(:inherit, _participant_ids), do: {:ok, :inherit}

  defp resolve_routes(routes, participant_ids) when is_map(routes) do
    Enum.reduce_while(routes, {:ok, %{}}, fn {source, recipients}, {:ok, resolved} ->
      with {:ok, source_id} <- Map.fetch(participant_ids, source),
           {:ok, recipient_ids} <- resolve_recipients(recipients, participant_ids) do
        {:cont, {:ok, Map.put(resolved, source_id, MapSet.new(recipient_ids))}}
      else
        :error -> {:halt, :error}
      end
    end)
  end

  defp resolve_routes(_routes, _participant_ids), do: :error

  defp resolve_recipients(recipients, participant_ids) when is_list(recipients) do
    Enum.reduce_while(recipients, {:ok, []}, fn recipient, {:ok, resolved} ->
      case Map.fetch(participant_ids, recipient) do
        {:ok, participant_id} -> {:cont, {:ok, [participant_id | resolved]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp resolve_recipients(_recipients, _participant_ids), do: :error

  defp valid_routes?(:inherit), do: true

  defp valid_routes?(routes) when is_map(routes) do
    Enum.all?(routes, fn
      {source_id, %MapSet{} = recipients} when is_binary(source_id) ->
        Enum.all?(recipients, &is_binary/1)

      {_source_id, _recipients} ->
        false
    end)
  end

  defp valid_routes?(_routes), do: false

  defp validate_permission(:inherit), do: :ok
  defp validate_permission(value) when is_boolean(value), do: :ok
  defp validate_permission(_value), do: :error
end
