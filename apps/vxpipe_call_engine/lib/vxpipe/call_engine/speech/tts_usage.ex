defmodule Vxpipe.CallEngine.Speech.TTSUsage do
  @moduledoc """
  A payload-free cumulative TTS usage snapshot.

  Snapshots travel inside the existing bounded event and audio envelopes. They
  contain no input text or generated PCM and remain historical evidence after
  the live envelope is acknowledged or revoked.
  """

  @enforce_keys [
    :session,
    :request_ref,
    :input_characters,
    :usage_identity,
    :provider_request_id,
    :provenance,
    :generated_bytes,
    :generation
  ]
  @derive {Inspect,
           only: [
             :request_ref,
             :input_characters,
             :generated_bytes,
             :generation
           ]}
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @doc false
  def snapshot(_allocation, %{kind: :sts}), do: nil

  def snapshot(allocation, %{submitted?: true} = request) do
    %__MODULE__{
      session: allocation,
      request_ref: request.ref,
      input_characters: request.input_characters,
      usage_identity: request.usage_identity,
      provider_request_id: request.provider_request_id,
      provenance: request.provenance,
      generated_bytes: request.generated_bytes,
      generation: generation(request)
    }
  end

  def snapshot(_allocation, _request), do: nil

  defp generation(%{terminal_result: result}) when result in [:completed, :cancelled], do: result
  defp generation(%{generated_bytes: bytes}) when bytes > 0, do: :generating
  defp generation(_request), do: :submitted
end
