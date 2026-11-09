defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.ToolStartup do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.PlanStartup.SpeechToSpeechActivation
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.{Evidence, OriginRecovery}
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor

  def deadline(_state, %{remote_mcp: nil}), do: nil

  def deadline(%{startup_ready?: true}, _runtime) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    timeout = settings |> Keyword.fetch!(:call_lifecycle) |> Keyword.fetch!(:readiness_timeout_ms)
    System.monotonic_time(:millisecond) + timeout
  end

  def deadline(state, _runtime), do: state.startup.deadline_ms

  def prepare(_state, capability, %{remote_mcp: nil} = runtime, deadline),
    do: {:ok, capability, runtime, deadline, nil}

  def prepare(state, capability, runtime, deadline) do
    plan = state.participant_transfer_runtime.plan
    participant = Map.fetch!(plan.participants, plan.entry_receiver)
    options = state.participant_transfer_runtime.startup_options

    with owner when is_pid(owner) <- Tree.remote_mcp_owner(capability),
         true <- participant.participant_id == runtime.participant_id,
         {:ok, registry} <- SpeechToSpeechActivation.registry(plan, participant, options, owner) do
      {:ok, capability, %{runtime | tool_registry: registry}, deadline, owner}
    else
      _failed ->
        RoomCapabilitySupervisor.stop_capability(state.snapshot.incarnation_id, capability)
        {:error, :tool_binding_unavailable}
    end
  end

  def bind(state, capability, deadline, owner) do
    timer =
      if owner && state.startup_ready? do
        Process.send_after(
          self(),
          {:vxpipe_sts_readiness_timeout, capability, deadline},
          max(deadline - System.monotonic_time(:millisecond), 0)
        )
      end

    binding =
      Map.merge(state.speech_to_speech_capability, %{
        tools_ready?: is_nil(owner),
        mcp_owner: owner,
        mcp_deadline: deadline,
        mcp_timer: timer
      })

    %{state | speech_to_speech_capability: binding}
  end

  def provider_ready(state, capability) do
    if Evidence.current?(state, capability) do
      state
      |> put_in([Access.key!(:speech_to_speech_capability), :provider_ready?], true)
      |> finish_ready()
    else
      {:ok, state}
    end
  end

  def tools_ready(state, owner, activation) do
    case state.speech_to_speech_capability do
      %{pid: capability, mcp_owner: ^owner, activation_id: ^activation} when is_pid(owner) ->
        if Tree.remote_mcp_owner(capability) == owner and
             state.speech_to_speech_runtime.activation_id == activation do
          state
          |> put_in([Access.key!(:speech_to_speech_capability), :tools_ready?], true)
          |> finish_ready()
        else
          {:ok, state}
        end

      _stale ->
        {:ok, state}
    end
  end

  def timeout(state, capability, deadline) do
    case state.speech_to_speech_capability do
      %{pid: ^capability, mcp_deadline: ^deadline} when not state.speech_to_speech_ready? ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: {:stop, {:shutdown, :sts_readiness_timeout}, state},
          else: {:noreply, state}

      _settled ->
        {:noreply, state}
    end
  end

  def cancel_timer(%{speech_to_speech_capability: %{mcp_timer: timer}}) when is_reference(timer),
    do: Process.cancel_timer(timer)

  def cancel_timer(_state), do: :ok

  defp finish_ready(%{speech_to_speech_ready?: true} = state), do: {:ok, state}

  defp finish_ready(%{speech_to_speech_capability: binding} = state) do
    if binding.provider_ready? and binding.tools_ready? and Map.has_key?(binding, :input_handle) do
      before_deadline? =
        is_nil(binding.mcp_deadline) or
          System.monotonic_time(:millisecond) < binding.mcp_deadline

      with true <- before_deadline?,
           %{speech_to_speech_ready?: true} = ready <-
             state
             |> SpeechToSpeech.prepare_input(binding.pid)
             |> OriginRecovery.restore_ready() do
        cancel_timer(state)
        {:ok, ready}
      else
        _failed -> {:error, :speech_to_speech_unavailable}
      end
    else
      {:ok, state}
    end
  end
end
