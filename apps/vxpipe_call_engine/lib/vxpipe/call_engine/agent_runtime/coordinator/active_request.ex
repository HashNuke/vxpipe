defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.ActiveRequest do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Input, Session}
  alias Vxpipe.CallEngine.AgentRuntime.{CompletionContinuation, Correlation, OutputBuffer}
  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.Guardrails.{Deadline, Evidence, Participant}
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.{Id, Telemetry}

  @derive {Inspect, only: [:kind, :first_output_observed?]}
  @enforce_keys [:command, :correlation, :kind, :output, :started_at, :task]
  defstruct @enforce_keys ++
              [
                phase: :session,
                first_output_observed?: false,
                continuation_started?: false,
                proposed_speech: nil
              ]

  @type kind :: :caller | :caller_idle | :greeting | {:completion, CompletionContinuation.t()}
  @type t :: %__MODULE__{
          command: SendText.t() | ContinueAgent.t(),
          correlation: Correlation.t(),
          kind: kind(),
          phase: :before_turn | :session,
          output: OutputBuffer.t(),
          started_at: integer(),
          task: Task.t(),
          first_output_observed?: boolean(),
          continuation_started?: boolean()
        }

  @spec start_caller(SendText.t(), keyword()) :: {:ok, t()} | {:error, :unavailable}
  def start_caller(%SendText{} = command, options) do
    correlation = correlation(command, options, :caller)

    case Keyword.get(options, :guardrails) do
      nil ->
        task = caller_task(:passed, command, correlation, options)
        new(command, correlation, :caller, task, options)

      server ->
        task = before_turn_task(server, command, correlation.deadline_ms, options)
        {:ok, request} = new(command, correlation, :caller, task, options)
        {:ok, %{request | phase: :before_turn}}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec submit_checked(t(), Vxpipe.CallEngine.Guardrails.CheckClient.verdict(), keyword()) ::
          {:ok, t()} | {:error, :unavailable}
  def submit_checked(%__MODULE__{}, {:error, _reason}, _options), do: {:error, :unavailable}

  def submit_checked(%__MODULE__{phase: :before_turn} = request, verdict, options) do
    task = caller_task(verdict, request.command, request.correlation, options)
    {:ok, %{request | phase: :session, task: task}}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp caller_task({:blocked, messages}, command, correlation, options),
    do: caller_task({:blocked, messages, nil}, command, correlation, options)

  defp caller_task(verdict, command, correlation, options) do
    session = Keyword.fetch!(options, :session)

    Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
      case Keyword.get(options, :guardrails) do
        nil ->
          Session.request(session, command.model_input || command.content, correlation, :infinity)

        server ->
          {kind, input} =
            case verdict do
              :passed ->
                {:caller, command.model_input || command.content}

              {:blocked, messages, callback} ->
                trigger =
                  if command.model_input,
                    do: Input.encode(command.model_input),
                    else: command.content

                {:private, {:feedback, blocked_feedback(messages), trigger, callback}}
            end

          revision = Map.get(command.source_transcript_policy || %{}, "media_policy_revision")

          permitted? = fn ->
            Participant.input_permitted?(server, command.participant_id, revision)
          end

          Session.request_guarded(session, kind, input, correlation, permitted?, :infinity)
      end
    end)
  end

  defp before_turn_task(server, command, deadline_ms, options) do
    evidence = %{
      "text" => command.content,
      "correlation" => %{
        "source_participant_id" => command.participant_id,
        "source_policy_revision" =>
          Map.get(command.source_transcript_policy || %{}, "media_policy_revision"),
        "source_turn_id" => command.correlation_id,
        "command_id" => command.id
      }
    }

    proposal = command.correlation_id
    deadline = Deadline.evaluation(deadline_ms)

    Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
      recent = options |> Keyword.fetch!(:session) |> Session.recent_dialogue()
      context = Evidence.recent(recent, Keyword.fetch!(options, :agent_participant_id))
      before_turn_check(server, proposal, Map.put(evidence, "recent_context", context), deadline)
    end)
  end

  @spec start_greeting(SendText.t(), keyword()) :: {:ok, t()} | {:error, :unavailable}
  def start_greeting(%SendText{} = command, options) do
    {:ok, input} = Input.platform(:greeting_request, %{}, :listener)
    correlation = correlation(command, options, :engine)
    session = Keyword.fetch!(options, :session)

    task =
      Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
        Session.continue(session, input, correlation, :infinity)
      end)

    new(command, correlation, :greeting, task, options)
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec start_caller_idle(SendText.t(), keyword()) :: {:ok, t()} | {:error, :unavailable}
  def start_caller_idle(%SendText{} = command, options) do
    {:ok, input} = Input.platform(:idle_timeout, %{}, :listener)
    correlation = correlation(command, options, :engine)
    session = Keyword.fetch!(options, :session)

    task =
      Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
        Session.continue(session, input, correlation, :infinity)
      end)

    new(command, correlation, :caller_idle, task, options)
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec correlation(SendText.t(), keyword(), :caller | :engine) :: Correlation.t()
  def correlation(%SendText{} = command, options, origin \\ :engine) do
    deadline = guarded_deadline(command, options)
    context = tool_context(command, Id.generate(:agent_request), options, origin)

    Correlation.new(Keyword.fetch!(options, :invocation_registry), context)
    |> put_deadline(deadline)
  end

  defp guarded_deadline(command, options) do
    if options[:guardrails], do: Deadline.response(command, options[:request_timeout_ms])
  end

  defp put_deadline(correlation, nil), do: correlation

  defp put_deadline(correlation, deadline) do
    %{
      correlation
      | deadline_ms: deadline,
        tool_context: %{correlation.tool_context | deadline_ms: deadline}
    }
  end

  @spec start_completion(CompletionContinuation.t(), keyword()) ::
          {:ok, t()} | {:error, :unavailable}
  def start_completion(%CompletionContinuation{} = continuation, options) do
    correlation =
      put_deadline(continuation.correlation, guarded_deadline(continuation.command, options))

    continuation = %{continuation | correlation: correlation}
    session = Keyword.fetch!(options, :session)

    task =
      Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
        Session.continue_tool_result(
          session,
          continuation.command.content,
          continuation.correlation,
          :infinity
        )
      end)

    new(
      continuation.command,
      continuation.correlation,
      {:completion, continuation},
      task,
      options
    )
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec push(t(), String.t()) :: {:ok, t(), [String.t()]} | {:error, :invalid_response}
  def push(%__MODULE__{} = request, text) do
    case OutputBuffer.push(request.output, text) do
      {:ok, output, segments} -> {:ok, %{request | output: output}, segments}
      {:error, :invalid_response} = error -> error
    end
  end

  @spec finish(t(), String.t()) :: {:ok, [String.t()]} | {:error, :invalid_response}
  def finish(%__MODULE__{} = request, output), do: OutputBuffer.finish(request.output, output)

  @spec observe_output(t(), String.t()) :: {t(), :first | :subsequent}
  def observe_output(%__MODULE__{first_output_observed?: false} = request, text)
      when is_binary(text) and text != "" do
    {%{request | first_output_observed?: true}, :first}
  end

  def observe_output(%__MODULE__{} = request, _text), do: {request, :subsequent}

  @spec mark_continuation_started(t()) :: t()
  def mark_continuation_started(%__MODULE__{} = request) do
    %{request | continuation_started?: true}
  end

  @spec cancel(t(), GenServer.server(), timeout()) :: :ok
  def cancel(%__MODULE__{phase: :before_turn} = request, _session, _timeout) do
    _ = Task.shutdown(request.task, :brutal_kill)
    :ok
  end

  def cancel(%__MODULE__{} = request, session, timeout) do
    _ = Session.cancel(session, timeout)
    _ = Task.shutdown(request.task, :brutal_kill)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp before_turn_check(server, proposal, evidence, deadline) do
    case Vxpipe.CallEngine.Guardrails.CheckClient.check_with_receipt(
           server,
           :before_turn,
           proposal,
           evidence,
           deadline
         ) do
      :passed -> :passed
      {:blocked, _} = blocked -> blocked
      {:blocked, _, _} = blocked -> blocked
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_result}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp blocked_feedback(messages) when is_list(messages) do
    Vxpipe.AgentRuntime.GuardrailFeedback.encode([%{event: :before_turn, messages: messages}])
  end

  defp new(command, correlation, kind, task, options) do
    {:ok,
     %__MODULE__{
       command: command,
       correlation: correlation,
       kind: kind,
       output: OutputBuffer.new(Keyword.fetch!(options, :maximum_output_bytes)),
       started_at: Telemetry.started_at(),
       task: task
     }}
  end

  defp tool_context(command, request_id, options, origin) do
    agent_participant_id = Keyword.fetch!(options, :agent_participant_id)

    %Context{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      agent_participant_id: agent_participant_id,
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      agent_request_id: request_id,
      tool_call_id: nil,
      request_origin: origin,
      source_policy_revision:
        Map.get(command.source_transcript_policy || %{}, "media_policy_revision"),
      agent_policy_revision:
        if(options[:guardrails],
          do: Evidence.agent_revision(command.incarnation_id, agent_participant_id)
        ),
      structured_caller_input?: match?(%Input{}, command.model_input),
      audio_response: command.audio_response
    }
  end
end
