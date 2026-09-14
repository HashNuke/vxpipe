defmodule Vxpipe.CallEngine.Readiness.Blockers do
  @moduledoc false

  def kinds(blockers), do: blockers |> Enum.map(&kind/1) |> Enum.uniq() |> Enum.sort()

  defp kind(%{kind: kind}), do: kind(kind)

  defp kind(kind)
       when kind in [
              :speech_to_text,
              :text_to_speech,
              :model_inference,
              :opening_audio,
              :tools,
              :recording,
              :room_services,
              :media,
              :other
            ],
       do: kind

  defp kind(:speech_to_text_ingress), do: :speech_to_text
  defp kind(kind) when kind in [:tool_invocations, :remote_tools], do: :tools

  defp kind(kind)
       when kind in [:recording_writer, :recording_output, :recording, :archive],
       do: :recording

  defp kind(kind)
       when kind in [:room_mixer, :transcript_router, :call_variables, :live_inspection],
       do: :room_services

  defp kind(kind)
       when kind in [
              :audio_input,
              :audio_output,
              :audio_subscription,
              :media_connection,
              :media_input,
              :phone_transport,
              :private_output,
              :room_output_binding
            ],
       do: :media

  defp kind(_kind), do: :other
end
