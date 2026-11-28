defmodule Vxpipe.CallEngine.RoomAuthority.Client do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.{
    AttachConnection,
    JoinParticipant,
    ParticipantTransferControl,
    SendText
  }

  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Tool.Context, as: ToolContext
  alias Vxpipe.CallEngine.Tool.Idle.Request, as: IdleRequest
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request, as: TransferRequest

  @call_timeout 5_000
  @transfer_timeout 122_000

  def snapshot(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :snapshot, @call_timeout)
  end

  def input_admission(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :input_admission, @call_timeout)
  end

  @doc "Captures current resource bindings without querying their dependencies."
  def readiness_binding(room_authority, timeout \\ 1_000) do
    GenServer.call(room_authority, :readiness_binding, timeout)
  end

  def join_participant(room_authority, %JoinParticipant{} = command, incarnation \\ nil) do
    GenServer.call(room_authority, {:join_participant, command, incarnation}, @call_timeout)
  end

  def attach_connection(
        room_authority,
        %AttachConnection{} = command,
        subscriber,
        output_sink,
        room_monitor,
        source_control? \\ false
      )
      when is_pid(subscriber) and is_reference(room_monitor) and is_boolean(source_control?) do
    GenServer.call(
      room_authority,
      {:attach_connection, command, subscriber, output_sink, room_monitor, source_control?},
      @call_timeout
    )
  end

  @spec participant_transfer_control(pid(), ParticipantTransferControl.t()) ::
          :ok | {:error, Error.t()}
  def participant_transfer_control(room_authority, %ParticipantTransferControl{} = command) do
    GenServer.call(room_authority, {:participant_transfer_control, command}, @call_timeout)
  end

  def send_text(room_authority, %SendText{} = command) do
    GenServer.call(room_authority, {:send_text, command}, @call_timeout)
  end

  @spec transfer(TransferRequest.t()) ::
          {:ok, map()} | {:error, :rejected | :unavailable}
  def transfer(%TransferRequest{} = request) do
    GenServer.call(
      via(request.tenant_id, request.room_id),
      {:transfer_participant, request},
      @transfer_timeout +
        if(request.announcement, do: Vxpipe.CallEngine.Tool.Announcement.budget_ms(), else: 0)
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec announce_hangup(ToolContext.t(), String.t()) :: :ok | {:error, :rejected | :unavailable}
  def announce_hangup(context, text) do
    GenServer.call(
      via(context.tenant_id, context.room_id),
      {:announce_hangup, context, text},
      Vxpipe.CallEngine.Tool.Announcement.budget_ms() + @call_timeout
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec terminal_submission_admission(ToolContext.t()) ::
          :ok | {:error, :caller_answer_pending | :unavailable}
  def terminal_submission_admission(%ToolContext{} = context) do
    GenServer.call(
      via(context.tenant_id, context.room_id),
      {:terminal_submission_admission, context},
      500
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @doc """
  Records a Decisions evaluation report from the owning participant activation.
  Trusted scope, stale activation and source-interval privacy are enforced
  room-side; untrusted or stale reports are dropped. Never blocks the caller.
  """
  @spec record_decisions(String.t(), String.t(), map()) :: :ok
  def record_decisions(tenant_id, room_id, report)
      when is_binary(tenant_id) and is_binary(room_id) and is_map(report) do
    notify(tenant_id, room_id, {:decisions_report, report})
  end

  @doc """
  Records late billable Decisions usage without reopening the gate.
  """
  @spec record_decisions_usage(String.t(), String.t(), [struct()]) :: :ok
  def record_decisions_usage(tenant_id, room_id, observations)
      when is_binary(tenant_id) and is_binary(room_id) and is_list(observations) do
    notify(tenant_id, room_id, {:decisions_late_usage, observations})
  end

  @doc """
  Records an invocation-bound Before-outgoing-transfer verdict produced by
  joint admission. Passed-only entries are stored; the room consumes each
  entry once when the terminal tool executes.
  """
  @spec bind_transfer_verdict(GenServer.server(), map()) ::
          :ok | {:error, :invalid_verdict | :unavailable}
  def bind_transfer_verdict(room_authority, entry) when is_map(entry) do
    GenServer.call(room_authority, {:bind_transfer_verdict, entry}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def bind_transfer_verdict(tenant_id, room_id, entry) do
    bind_transfer_verdict(via(tenant_id, room_id), entry)
  end

  @doc """
  Peeks at the bound verdict for an invocation without consuming it.
  Consumption happens once at transfer begin with identity revalidation.
  """
  @spec take_transfer_verdict(String.t(), String.t(), {String.t(), String.t()}) ::
          {:ok, map()} | :empty | {:error, :unavailable}
  def take_transfer_verdict(tenant_id, room_id, {command, invocation} = key)
      when is_binary(tenant_id) and is_binary(room_id) and is_binary(command) and
             is_binary(invocation) do
    GenServer.call(
      via(tenant_id, room_id),
      {:take_transfer_verdict, key},
      @call_timeout
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @doc """
  Records a guardrail policy denial for a transfer that never reached the
  preparation. The request identifies the originating activation and invocation.
  """
  @spec note_transfer_denial(String.t(), String.t(), map()) :: :ok
  def note_transfer_denial(tenant_id, room_id, note)
      when is_binary(tenant_id) and is_binary(room_id) and is_map(note) do
    notify(tenant_id, room_id, {:note_transfer_denial, note})
  end

  @spec idle(IdleRequest.t()) :: {:ok, map()} | {:error, :rejected | :unavailable}
  def idle(%IdleRequest{} = request) do
    GenServer.call(
      via(request.context.tenant_id, request.context.room_id),
      {:idle, request},
      IdleRequest.execution_timeout_ms(request)
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def speech_to_text_configuration(room_authority, %AttachConnection{} = command) do
    GenServer.call(room_authority, {:speech_to_text_configuration, command}, @call_timeout)
  end

  def prepare_transfer_speech_to_text(room_authority, %AttachConnection{} = command, attempt_id) do
    GenServer.call(
      room_authority,
      {:prepare_transfer_speech_to_text, command, attempt_id},
      @call_timeout
    )
  end

  def prepare_transfer_media(room_authority, %AttachConnection{} = command, attempt_id) do
    GenServer.call(room_authority, {:prepare_transfer_media, command, attempt_id}, @call_timeout)
  end

  def bind_speech_to_text(
        room_authority,
        %AttachConnection{} = command,
        subscriber,
        capability,
        ingress
      )
      when is_pid(subscriber) and is_pid(capability) and is_pid(ingress) do
    GenServer.call(
      room_authority,
      {:bind_speech_to_text, command, subscriber, capability, ingress},
      @call_timeout
    )
  end

  def detach_connection(room_authority, %AttachConnection{} = command, subscriber)
      when is_pid(subscriber) do
    GenServer.call(room_authority, {:detach_connection, command, subscriber}, @call_timeout)
  end

  defp notify(tenant_id, room_id, message) do
    if pid = GenServer.whereis(via(tenant_id, room_id)), do: send(pid, message)
    :ok
  catch
    :exit, _reason -> :ok
  end

  def via(tenant_id, room_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}}}
  end
end
