defmodule Vxpipe.CallEngine.AgentRuntime.CompletionContinuation do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session
  alias Vxpipe.CallEngine.AgentRuntime.Correlation
  alias Vxpipe.CallEngine.Command.ContinueAgent
  alias Vxpipe.CallEngine.Tool.{CompletionLease, InvocationRegistry}

  @derive {Inspect, only: [:invocation_id]}
  @enforce_keys [:invocation_id, :command, :correlation, :lease]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          invocation_id: String.t(),
          command: ContinueAgent.t(),
          correlation: Correlation.t(),
          lease: CompletionLease.t()
        }

  @spec lease_next(GenServer.server(), String.t()) ::
          {:ok, t()} | {:error, :empty | :held | :unavailable}
  def lease_next(invocation_registry, consumer_id) do
    case InvocationRegistry.lease_for_model(invocation_registry, consumer_id) do
      {:ok, %CompletionLease{} = lease} ->
        command = ContinueAgent.new(lease.completion)

        tool_context = %{
          lease.completion.context
          | command_id: command.id,
            correlation_id: command.correlation_id,
            tool_call_id: nil,
            request_origin: :engine
        }

        {:ok,
         %__MODULE__{
           invocation_id: lease.invocation_id,
           command: command,
           correlation: Correlation.new(invocation_registry, tool_context),
           lease: lease
         }}

      {:error, reason} when reason in [:empty, :held, :unavailable] ->
        {:error, reason}

      _invalid ->
        {:error, :unavailable}
    end
  end

  @doc "Retains the terminal fact exactly once when its model request fails or its source departs."
  @spec retain(t(), GenServer.server(), GenServer.server()) :: :ok | {:error, :unavailable}
  def retain(continuation, session, invocation_registry) do
    with {:ok, durable?} <- Session.durable?(session, continuation.correlation),
         :ok <- record_observation(durable?, session, continuation) do
      acknowledge(invocation_registry, continuation)
    else
      _unavailable -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  # Host-settled history retains the input at admission. Generated history
  # may also have committed it with an accepted nested tool exchange.
  defp record_observation(true, _session, _continuation), do: :ok

  defp record_observation(false, session, continuation),
    do:
      Session.retain_tool_result(session, continuation.command.content, continuation.correlation)

  @spec acknowledge(GenServer.server(), t()) :: :ok | {:error, :unavailable}
  def acknowledge(invocation_registry, %__MODULE__{} = continuation) do
    InvocationRegistry.acknowledge_completion(
      invocation_registry,
      continuation.invocation_id,
      continuation.lease.lease_id
    )
  end

  @spec release(GenServer.server(), t()) :: :ok | {:error, :unavailable}
  def release(invocation_registry, %__MODULE__{} = continuation) do
    InvocationRegistry.release_completion(
      invocation_registry,
      continuation.invocation_id,
      continuation.lease.lease_id
    )
  end
end
