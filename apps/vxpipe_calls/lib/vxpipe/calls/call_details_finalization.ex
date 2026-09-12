defmodule Vxpipe.Calls.CallDetailsFinalization do
  @moduledoc "Assesses persisted call facts and submits publishable immutable details snapshots."

  alias Vxpipe.Calls.{
    CallDetailsAssessment,
    CallDetailsSnapshot,
    PublicId,
    PublicationDecision,
    PublicationSources,
    PublicationWindow,
    PublicationWorkers
  }

  @default_window_seconds 60

  @type result ::
          {:wait, PublicationDecision.t()}
          | {:publish, PublicationDecision.t(), CallDetailsSnapshot.t(), pid(),
             :started | :existing}
          | {:error, term()}

  @spec assess(String.t(), String.t(), DateTime.t(), keyword()) :: result()
  def assess(tenant_key, call_id, %DateTime{} = assessed_at, options)
      when is_binary(tenant_key) and tenant_key != "" and is_binary(call_id) and call_id != "" and
             is_list(options) do
    with {:ok, {source, context}} <- PublicationSources.fetch(options),
         {:ok, %CallDetailsAssessment{} = assessment} <- source.read(context, tenant_key, call_id),
         :ok <- identity(assessment, tenant_key, call_id),
         {:ok, decision} <- decision(assessment, assessed_at, options) do
      act(decision, assessment, tenant_key, call_id, assessed_at, options)
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_call_details_assessment}
    end
  end

  def assess(_tenant_key, _call_id, _assessed_at, _options),
    do: {:error, :invalid_call_details_assessment}

  defp decision(assessment, assessed_at, options) do
    PublicationWindow.evaluate(
      assessment.ended_at,
      assessed_at,
      assessment.components,
      window_seconds: window_seconds(options)
    )
  end

  defp act(
         %PublicationDecision{action: :wait} = decision,
         _assessment,
         _tenant,
         _call,
         _at,
         _opts
       ),
       do: {:wait, decision}

  defp act(decision, assessment, tenant_key, call_id, assessed_at, options) do
    publication_id = Keyword.get_lazy(options, :publication_id, &PublicId.uuid/0)

    with {:ok, snapshot} <-
           CallDetailsSnapshot.new(publication_id, assessed_at, assessment.source, decision),
         {:ok, worker, disposition} <-
           PublicationWorkers.start(tenant_key, call_id, snapshot, options) do
      {:publish, decision, snapshot, worker, disposition}
    end
  end

  defp identity(assessment, tenant_key, call_id) do
    identity = assessment.source.call["identity"]

    if identity["tenant_key"] == tenant_key and identity["call_id"] == call_id,
      do: :ok,
      else: {:error, :publication_source_scope_mismatch}
  end

  defp window_seconds(options) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    publication = Keyword.get(configured, :call_details_publication, [])

    Keyword.get(
      options,
      :window_seconds,
      Keyword.get(publication, :window_seconds, @default_window_seconds)
    )
  end
end
