defmodule Vxpipe.AgentRuntime.Session.RequestWorker do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{RequestRunner, SessionConfiguration}

  def start(configuration, conversation, request, overrides) do
    session = self()
    token = make_ref()
    timeout = configuration.commit_timeout_ms
    emit = &emit_request_event(session, token, &1, &2, configuration.event_handoff_timeout_ms)

    usage = fn kind, value, metadata, outcome ->
      emit.(kind, %{usage: value, provider_metadata: metadata, outcome: outcome})
    end

    callbacks = %{
      begin_submission: fn -> begin_submission(session, token, timeout) end,
      commit: &commit_conversation(session, token, &1, timeout),
      emit_text_delta: &emit.(:text_delta, %{text: &1}),
      emit_model_attempt: &emit.(&1, %{}),
      emit_model_usage: &usage.(:model_usage, &1, &2, &3),
      emit_context_compaction_usage: &usage.(:context_compaction_usage, &1, &2, &3)
    }

    options =
      configuration |> SessionConfiguration.runner_options(callbacks) |> Map.merge(overrides)

    task =
      Task.Supervisor.async(Vxpipe.AgentRuntime.RequestSupervisor, fn ->
        RequestRunner.run(conversation, request, options)
      end)

    {task, token}
  end

  defp begin_submission(session, token, timeout_ms) do
    send(session, {:agent_runtime_begin_submission, self(), token})

    receive do
      {:agent_runtime_submission_begun, ^token} -> :ok
      {:agent_runtime_submission_aborted, ^token} -> {:error, :stale}
    after
      timeout_ms -> {:error, :commit_unavailable}
    end
  end

  defp commit_conversation(session, token, conversation, timeout_ms) do
    send(session, {:agent_runtime_commit, self(), token, conversation})

    receive do
      {:agent_runtime_committed, ^token} -> :ok
    after
      timeout_ms -> {:error, :commit_unavailable}
    end
  end

  defp emit_request_event(session, token, kind, data, timeout_ms) do
    event_ref = make_ref()
    send(session, {:agent_runtime_request_event, self(), token, event_ref, kind, data})

    receive do
      {:agent_runtime_request_event_emitted, ^token, ^event_ref} -> :ok
    after
      timeout_ms -> {:error, :event_unavailable}
    end
  end
end
