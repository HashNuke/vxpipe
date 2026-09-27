defmodule Vxpipe.CallEngine.RoomAuthority.STSSourceCutover do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech, as: Capability
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.{Ingress, STSIngress}
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.RoomAuthority.STSSourceCutover.NativeInput
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech

  @connection_budget_ms 8_000
  @room_budget_ms 9_000

  def hold(%State{} = state, reason), do: hold(state, reason, nil)

  def hold(%State{source_cutover: %{}} = state, reason, old_generation) do
    cutover = state.source_cutover

    cutover =
      if is_reference(old_generation),
        do: %{cutover | old_stt_generation: old_generation},
        else: cutover

    if reason == :transfer do
      # An overlapping transfer hold blocks arm without discarding the reason
      # of the cutover already in flight.
      holds = MapSet.put(cutover.holds, :transfer)
      cutover = %{cutover | holds: holds, release_requested?: false}
      state = %{state | source_cutover: cutover}

      if cutover.phase == :held,
        do: NativeInput.retire(cutover.connection_id, state),
        else: state
    else
      # The ingress invalidation is authoritative for the retired generation;
      # keep the refreshed cutover instead of dropping the update.
      %{state | source_cutover: cutover}
    end
  end

  def hold(%State{} = state, reason, old_generation) when reason in [:transfer, :policy] do
    with {:ok, connection_id, connection} <- source_connection(state),
         true <- Map.get(connection, :source_control?, false) do
      ingress_close_ok? = close_inputs(state, connection) == :ok
      token = make_ref()
      deadline_ms = System.monotonic_time(:millisecond) + @connection_budget_ms

      request_id =
        :gen_server.send_request(
          connection.pid,
          {:vxpipe_sts_source_hold,
           %{attachment: connection.room_monitor, token: token, deadline_ms: deadline_ms}}
        )

      timer =
        Process.send_after(self(), {:vxpipe_sts_source_cutover_timeout, token}, @room_budget_ms)

      old_generation =
        if is_reference(old_generation), do: old_generation, else: stt_generation(connection)

      cutover = %{
        connection_id: connection_id,
        connection: connection.pid,
        attachment: connection.room_monitor,
        token: token,
        request_id: request_id,
        timer: timer,
        deadline_ms: deadline_ms,
        phase: :holding,
        reason: reason,
        holds: if(reason == :policy, do: MapSet.new(), else: MapSet.new([reason])),
        receipt: nil,
        active_epoch: nil,
        old_stt_generation: old_generation,
        stt_ready?: is_nil(Map.get(connection, :speech_to_text)),
        release_requested?: reason == :policy,
        sts_ready?: SpeechToSpeech.ready?(state),
        ingress_close_ok?: ingress_close_ok?,
        fresh_stt?: false,
        policy_from: nil
      }

      %{state | source_cutover: cutover}
    else
      false -> state
      {:error, _reason} -> state
    end
  catch
    :exit, _reason -> state
  end

  def hold(%State{} = state, _reason, _old_generation), do: state

  def release(%State{source_cutover: nil}), do: :not_applicable

  def release(%State{source_cutover: cutover} = state) do
    holds = MapSet.delete(cutover.holds, :transfer)

    cutover = %{
      cutover
      | holds: holds,
        release_requested?: MapSet.size(holds) == 0,
        sts_ready?:
          SpeechToSpeech.ready?(state) or
            (is_nil(state.speech_to_speech_capability) and is_nil(state.speech_to_speech_recovery))
    }

    maybe_arm(%{state | source_cutover: cutover})
  end

  def connected(
        %State{source_cutover: %{connection_id: connection_id} = cutover} = state,
        connection_id,
        capability,
        signal
      ) do
    with %{speech_to_text: %{capability: ^capability}} <-
           Map.get(state.connections, connection_id),
         true <- signal.kind == :connected,
         true <- signal.allocation_generation != cutover.old_stt_generation,
         {:ok, %{allocation_generation: generation}} <- SpeechToText.input_binding(capability),
         true <- generation == signal.allocation_generation do
      case cutover.phase do
        :holding ->
          %{state | source_cutover: %{cutover | fresh_stt?: true}}

        :held ->
          case NativeInput.bind_audio_origin(connection_id, state) do
            :ok -> maybe_arm(%{state | source_cutover: %{cutover | stt_ready?: true}})
            _error -> fail(state, :fresh_stt_origin_unavailable)
          end

        _other ->
          state
      end
    else
      _not_current -> state
    end
  catch
    :exit, _reason -> state
  end

  def connected(%State{} = state, _connection_id, _capability, _signal), do: state

  def handle_response(
        message,
        %State{source_cutover: %{request_id: request_id}} = state
      )
      when is_reference(request_id) do
    case :gen_server.check_response(message, request_id) do
      {:reply, result} -> response(result, state)
      {:error, reason} -> fail(state, {:connection_unavailable, reason})
      :no_reply -> :unmatched
    end
  end

  def handle_response(
        message,
        %State{source_cutover: %{late_request_id: request_id, phase: :failed}} = state
      ) do
    case :gen_server.check_response(message, request_id) do
      {:reply, _late_result} -> state
      {:error, _reason} -> state
      :no_reply -> :unmatched
    end
  end

  def handle_response(_message, _state), do: :unmatched

  def timeout(token, %State{source_cutover: %{token: token}} = state) do
    fail(state, :deadline_elapsed)
  end

  def timeout(_token, state), do: state

  def connection_down(
        connection_id,
        %State{source_cutover: %{connection_id: connection_id}} = state
      ),
      do: fail(state, :connection_unavailable)

  def connection_down(_connection_id, state), do: state

  def private_input_held?(%State{source_cutover: %{connection_id: connection_id}}, connection_id),
    do: true

  def private_input_held?(_state, _connection_id), do: false

  def active?(%State{source_cutover: cutover}), do: is_map(cutover)

  def native_ready?(%State{source_cutover: %{stt_ready?: ready?}}), do: ready?
  def native_ready?(_state), do: false

  defp response({:ok, receipt}, %State{source_cutover: %{phase: :holding} = cutover} = state) do
    Process.cancel_timer(cutover.timer)

    if valid_receipt?(receipt, cutover) do
      state = %{state | source_cutover: %{cutover | phase: :held, receipt: receipt}}
      state = if cutover.ingress_close_ok?, do: retire_source_recognizer(state), else: state
      state = bind_observed_source(state)

      state =
        if native_ready?(state) and is_map(state.speech_to_speech_recovery),
          do: SpeechToSpeech.recover(state),
          else: state

      maybe_arm(state)
    else
      fail(state, :invalid_source_receipt)
    end
  end

  defp response({:ok, epoch}, %State{source_cutover: %{phase: :arming} = cutover} = state)
       when epoch == cutover.active_epoch do
    Process.cancel_timer(cutover.timer)

    if MapSet.size(cutover.holds) > 0 do
      restart_hold(state, cutover)
    else
      case reopen(state, epoch) do
        {:ok, state} -> %{state | source_cutover: nil}
        {:error, reason, state} -> fail(state, reason)
      end
    end
  end

  defp response({:error, reason}, state), do: fail(state, {:source_rejected, reason})
  defp response(_unexpected, state), do: fail(state, :invalid_source_response)

  defp maybe_arm(%State{source_cutover: %{phase: :held} = cutover} = state) do
    if cutover.ingress_close_ok? and cutover.release_requested? and cutover.stt_ready? and
         cutover.sts_ready? and
         MapSet.size(cutover.holds) == 0 do
      arm(state, cutover)
    else
      state
    end
  end

  defp maybe_arm(state), do: state

  defp arm(state, cutover) do
    active_epoch = make_ref()
    deadline_ms = System.monotonic_time(:millisecond) + @connection_budget_ms

    request_id =
      :gen_server.send_request(
        cutover.connection,
        {:vxpipe_sts_source_arm,
         %{
           attachment: cutover.attachment,
           token: cutover.token,
           receipt: cutover.receipt,
           active_epoch: active_epoch,
           deadline_ms: deadline_ms
         }}
      )

    timer =
      Process.send_after(
        self(),
        {:vxpipe_sts_source_cutover_timeout, cutover.token},
        @room_budget_ms
      )

    %{
      state
      | source_cutover: %{
          cutover
          | request_id: request_id,
            timer: timer,
            deadline_ms: deadline_ms,
            phase: :arming,
            active_epoch: active_epoch
        }
    }
  end

  defp restart_hold(state, cutover) do
    case Map.get(state.connections, cutover.connection_id) do
      %{source_control?: true} = connection ->
        with :ok <- close_inputs(state, connection) do
          token = make_ref()
          deadline_ms = System.monotonic_time(:millisecond) + @connection_budget_ms

          request_id =
            :gen_server.send_request(
              connection.pid,
              {:vxpipe_sts_source_hold,
               %{attachment: connection.room_monitor, token: token, deadline_ms: deadline_ms}}
            )

          timer =
            Process.send_after(
              self(),
              {:vxpipe_sts_source_cutover_timeout, token},
              @room_budget_ms
            )

          %{
            state
            | source_cutover: %{
                cutover
                | token: token,
                  request_id: request_id,
                  timer: timer,
                  deadline_ms: deadline_ms,
                  phase: :holding,
                  receipt: nil,
                  active_epoch: nil,
                  stt_ready?: is_nil(Map.get(connection, :speech_to_text)),
                  release_requested?: false,
                  ingress_close_ok?: true
              }
          }
        else
          {:error, reason} -> fail(state, reason)
        end

      _source_gone ->
        fail(state, :source_unavailable)
    end
  end

  defp reopen(state, source_epoch) do
    state = release_sts(state)

    case open_stt(state, source_epoch) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp release_sts(%State{speech_to_speech_capability: nil} = state), do: state

  defp release_sts(%State{speech_to_speech_capability: %{pid: capability}} = state) do
    epoch = make_ref()

    case Capability.release(capability, epoch) do
      :ok ->
        binding = Map.put(state.speech_to_speech_capability, :input_epoch, epoch)
        %{state | speech_to_speech_capability: binding}

      {:error, _reason} ->
        SpeechToSpeech.stop(state)
    end
  catch
    :exit, _reason -> SpeechToSpeech.stop(state)
  end

  defp open_stt(%State{source_cutover: %{connection_id: connection_id}} = state, source_epoch) do
    case Map.get(state.connections, connection_id) do
      %{speech_to_text: %{ingress: ingress}} -> Ingress.open(ingress, source_epoch)
      _no_stt -> :ok
    end
  end

  defp retire_source_recognizer(%State{source_cutover: %{reason: :policy}} = state), do: state

  defp retire_source_recognizer(%State{source_cutover: %{connection_id: connection_id}} = state) do
    NativeInput.retire(connection_id, state)
  end

  defp close_inputs(connection) do
    stt_result =
      case Map.get(connection, :speech_to_text) do
        %{ingress: ingress} -> Ingress.close(ingress)
        _no_stt -> :ok
      end

    if stt_result == :ok,
      do: :ok,
      else: {:error, :input_close_failed}
  end

  defp close_inputs(state, connection) do
    with :ok <- close_inputs(connection),
         :ok <- close_sts_ingress(state) do
      :ok
    end
  end

  defp close_sts_ingress(%State{speech_to_speech_capability: %{ingress: ingress}})
       when is_pid(ingress),
       do: STSIngress.hold(ingress)

  defp close_sts_ingress(_state), do: :ok

  defp source_connection(
         %State{speech_to_speech_capability: %{connection_id: connection_id}} = state
       )
       when is_binary(connection_id) do
    case Map.fetch(state.connections, connection_id) do
      {:ok, connection} -> {:ok, connection_id, connection}
      :error -> {:error, :source_not_attached}
    end
  end

  defp source_connection(
         %State{speech_to_speech_recovery: %{connection_id: connection_id}} = state
       ) do
    case Map.fetch(state.connections, connection_id) do
      {:ok, connection} -> {:ok, connection_id, connection}
      :error -> {:error, :source_not_attached}
    end
  end

  defp source_connection(_state), do: {:error, :source_not_attached}

  defp stt_generation(%{speech_to_text: %{capability: capability}}) do
    case SpeechToText.input_binding(capability) do
      {:ok, %{allocation_generation: generation}} -> generation
      _not_ready -> nil
    end
  catch
    :exit, _reason -> nil
  end

  defp stt_generation(_connection), do: nil

  defp bind_observed_source(
         %State{
           source_cutover:
             %{connection_id: connection_id, old_stt_generation: old_generation} =
               cutover
         } = state
       ) do
    case Map.get(state.connections, connection_id) do
      %{speech_to_text: %{capability: capability}} ->
        case SpeechToText.input_binding(capability) do
          {:ok, %{status: :ready, allocation_generation: generation}}
          when is_reference(generation) and generation != old_generation ->
            case NativeInput.bind_audio_origin(connection_id, state) do
              :ok -> %{state | source_cutover: %{cutover | stt_ready?: true}}
              _error -> fail(state, :fresh_stt_origin_unavailable)
            end

          _not_fresh ->
            state
        end

      _no_stt ->
        state
    end
  catch
    :exit, _reason -> state
  end

  defp valid_receipt?(
         %{
           attachment: attachment,
           token: token,
           receiver: receiver,
           old_epoch: old_epoch,
           held_epoch: held_epoch
         },
         cutover
       ) do
    attachment == cutover.attachment and token == cutover.token and is_pid(receiver) and
      is_reference(old_epoch) and is_reference(held_epoch) and old_epoch != held_epoch
  end

  defp valid_receipt?(_receipt, _cutover), do: false

  defp fail(
         %State{source_cutover: %{timer: timer, request_id: request_id} = cutover} = state,
         reason
       ) do
    Process.cancel_timer(timer)

    if is_pid(Map.get(cutover, :policy_from)) do
      GenServer.reply(cutover.policy_from, {:error, reason})
    end

    # An ambiguous source result keeps both input lanes closed and retires the
    # STS allocation so no stale or unqualified audio can reach it.
    state = SpeechToSpeech.stop(state)

    %{
      state
      | source_cutover:
          cutover
          |> Map.put(:phase, :failed)
          |> Map.put(:failure, reason)
          |> Map.put(:late_request_id, request_id)
          |> Map.put(:request_id, nil)
    }
  end

  defp fail(state, _reason), do: state
end
