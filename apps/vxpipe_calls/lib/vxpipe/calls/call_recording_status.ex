defmodule Vxpipe.Calls.CallRecordingStatus do
  @moduledoc """
  Snapshot-aware call-level recording status.

  The admission decision (whether recording was requested and whether storage
  was configured) is snapshotted in the archived `room_opened` fact. Later
  reconfiguration must not reinterpret that decision. Old rows without a
  snapshot fall back to the resolved plan tri-state and current storage
  configuration.
  """

  @type plan_request :: :inherit | boolean()

  @spec plan_recording(term()) :: plan_request()
  def plan_recording(%{media_policy: %{record_audio: value}})
      when value in [:inherit, true, false],
      do: value

  def plan_recording(_plan), do: :inherit

  @spec configured_available?() :: boolean()
  def configured_available? do
    Application.get_env(:vxpipe_calls, :recording_available, true) != false
  end

  @spec snapshot_from_facts([map()]) :: %{requested: boolean(), configured: boolean()} | nil
  def snapshot_from_facts(facts) when is_list(facts) do
    facts
    |> Enum.filter(&(&1.kind == :room_opened))
    |> Enum.sort_by(& &1.sequence)
    |> Enum.find_value(nil, fn fact ->
      case fact.payload do
        %{"recording" => %{"requested" => requested, "configured" => configured}}
        when is_boolean(requested) and is_boolean(configured) ->
          %{requested: requested, configured: configured}

        _ ->
          nil
      end
    end)
  end

  @spec admission([map()], plan_request(), boolean()) :: %{
          requested: plan_request(),
          configured: boolean(),
          snapshotted: boolean()
        }
  def admission(facts, fallback_requested, fallback_configured)
      when is_list(facts) and fallback_requested in [:inherit, true, false] and
             is_boolean(fallback_configured) do
    case snapshot_from_facts(facts) do
      %{requested: requested, configured: configured} ->
        %{requested: requested, configured: configured, snapshotted: true}

      nil ->
        %{
          requested: fallback_requested,
          configured: fallback_configured,
          snapshotted: false
        }
    end
  end

  @spec permitted_artifacts([map()], plan_request(), [map()]) :: [map()]
  def permitted_artifacts(facts, fallback_requested, artifacts)
      when is_list(facts) and is_list(artifacts) do
    requested =
      case snapshot_from_facts(facts) do
        %{requested: requested} -> requested
        nil -> normalize_requested(fallback_requested)
      end

    if requested == false, do: [], else: artifacts
  end

  @spec status([map()], [map()], keyword()) :: String.t()
  def status(facts, artifacts, options \\ [])
      when is_list(facts) and is_list(artifacts) and is_list(options) do
    fallback_requested =
      options |> Keyword.get(:fallback_requested, :inherit) |> normalize_requested()

    fallback_configured =
      options
      |> Keyword.get(:fallback_configured, configured_available?())
      |> normalize_configured()

    decision = admission(facts, fallback_requested, fallback_configured)

    case decision do
      %{snapshotted: true} -> snapshotted_status(decision, artifacts)
      %{snapshotted: false} -> legacy_status(decision, artifacts)
    end
  end

  @spec component_decision([map()], [map()], keyword()) ::
          {:prohibited | :unconfigured | :pending | :complete | :failed | :missing, map()}
  def component_decision(facts, artifacts, options \\ [])
      when is_list(facts) and is_list(artifacts) and is_list(options) do
    case status(facts, artifacts, options) do
      "not_requested" ->
        {:prohibited, %{"policy" => "record_audio_disabled"}}

      "unavailable:prohibited_audio_present" ->
        {:failed, %{"reason" => "prohibited_audio_present"}}

      "unavailable:storage_unconfigured" ->
        {:unconfigured, %{"reason" => "storage_unconfigured"}}

      "unavailable:missing_recording" when artifacts == [] ->
        {:pending, %{"reason" => "missing_recording"}}

      "unavailable:missing_recording" ->
        failed_component(artifacts)

      "recorded" ->
        if Enum.any?(artifacts, &incomplete?/1),
          do: failed_component(artifacts),
          else: {:complete, %{"artifact_count" => length(artifacts)}}
    end
  end

  defp failed_component(artifacts) do
    {:failed,
     %{
       "reason" => "incomplete_recording",
       "artifact_count" => length(artifacts),
       "incomplete_artifact_count" => Enum.count(artifacts, &incomplete?/1)
     }}
  end

  defp normalize_requested(:inherit), do: :inherit
  defp normalize_requested(true), do: true
  defp normalize_requested(false), do: false
  defp normalize_requested(_other), do: :inherit

  defp normalize_configured(false), do: false
  defp normalize_configured(_other), do: true

  defp snapshotted_status(%{requested: false}, artifacts) do
    if Enum.any?(artifacts, &(sample_count(&1) > 0)),
      do: "unavailable:prohibited_audio_present",
      else: "not_requested"
  end

  defp snapshotted_status(%{requested: true, configured: configured}, artifacts) do
    requested_status(configured, artifacts)
  end

  defp legacy_status(%{requested: :inherit, configured: configured}, artifacts) do
    cond do
      any_usable?(artifacts) and configured -> "recorded"
      any_usable?(artifacts) -> "unavailable:storage_unconfigured"
      true -> "not_requested"
    end
  end

  defp legacy_status(%{requested: true, configured: configured}, artifacts) do
    requested_status(configured, artifacts)
  end

  defp legacy_status(%{requested: false}, artifacts) do
    if Enum.any?(artifacts, &(sample_count(&1) > 0)),
      do: "unavailable:prohibited_audio_present",
      else: "not_requested"
  end

  defp requested_status(false, _artifacts), do: "unavailable:storage_unconfigured"
  defp requested_status(true, []), do: "unavailable:missing_recording"

  defp requested_status(true, artifacts) do
    if any_usable?(artifacts), do: "recorded", else: "unavailable:missing_recording"
  end

  defp any_usable?(artifacts) when is_list(artifacts) do
    Enum.any?(artifacts, &usable?/1)
  end

  defp usable?(artifact) do
    sample_count(artifact) > 0 and has_object?(artifact)
  end

  defp has_object?(%{object_reference: %{"object_key" => key}})
       when is_binary(key) and key != "",
       do: true

  defp has_object?(%{"object_reference" => %{"object_key" => key}})
       when is_binary(key) and key != "",
       do: true

  defp has_object?(%{object_reference: %{object_key: key}})
       when is_binary(key) and key != "",
       do: true

  defp has_object?(_artifact), do: false

  defp incomplete?(%{status: :incomplete}), do: true
  defp incomplete?(%{"status" => "incomplete"}), do: true
  defp incomplete?(_), do: false

  defp sample_count(%{sample_count: count}) when is_integer(count), do: count
  defp sample_count(%{"sample_count" => count}) when is_integer(count), do: count
  defp sample_count(_), do: 0
end
