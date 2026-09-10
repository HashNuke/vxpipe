defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.ActiveRequest do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session
  alias Vxpipe.CallEngine.AgentRuntime.{CompletionContinuation, Correlation, OutputBuffer}
  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.{Id, Telemetry}

  @derive {Inspect, only: [:kind, :first_output_observed?]}
  @enforce_keys [:command, :correlation, :kind, :output, :started_at, :task]
  defstruct @enforce_keys ++ [first_output_observed?: false, continuation_started?: false]

  @type kind :: :caller | :greeting | {:completion, CompletionContinuation.t()}
  @type t :: %__MODULE__{
          command: SendText.t() | ContinueAgent.t(),
          correlation: Correlation.t(),
          kind: kind(),
          output: OutputBuffer.t(),
          started_at: integer(),
          task: Task.t(),
          first_output_observed?: boolean(),
          continuation_started?: boolean()
        }

  @spec start_caller(SendText.t(), keyword()) :: {:ok, t()} | {:error, :unavailable}
  def start_caller(%SendText{} = command, options) do
    request_id = Id.generate(:agent_request)
    context = tool_context(command, request_id, Keyword.fetch!(options, :agent_participant_id))
    correlation = Correlation.new(Keyword.fetch!(options, :invocation_registry), context)
    session = Keyword.fetch!(options, :session)

    task =
      Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
        Session.request(session, command.content, correlation, :infinity)
      end)

    new(command, correlation, :caller, task, options)
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec start_greeting(SendText.t(), keyword()) :: {:ok, t()} | {:error, :unavailable}
  def start_greeting(%SendText{} = command, options) do
    correlation = correlation(command, options)
    session = Keyword.fetch!(options, :session)

    task =
      Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
        Session.continue(session, command.content, correlation, :infinity)
      end)

    new(command, correlation, :greeting, task, options)
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec correlation(SendText.t(), keyword()) :: Correlation.t()
  def correlation(%SendText{} = command, options) do
    request_id = Id.generate(:agent_request)
    context = tool_context(command, request_id, Keyword.fetch!(options, :agent_participant_id))
    Correlation.new(Keyword.fetch!(options, :invocation_registry), context)
  end

  @spec start_completion(CompletionContinuation.t(), keyword()) ::
          {:ok, t()} | {:error, :unavailable}
  def start_completion(%CompletionContinuation{} = continuation, options) do
    session = Keyword.fetch!(options, :session)

    task =
      Task.Supervisor.async_nolink(Keyword.fetch!(options, :request_supervisor), fn ->
        Session.continue(
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
  def cancel(%__MODULE__{} = request, session, timeout) do
    _ = Session.cancel(session, timeout)
    _ = Task.shutdown(request.task, :brutal_kill)
    :ok
  catch
    :exit, _reason -> :ok
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

  defp tool_context(command, request_id, agent_participant_id) do
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
      audio_response: command.audio_response
    }
  end
end
