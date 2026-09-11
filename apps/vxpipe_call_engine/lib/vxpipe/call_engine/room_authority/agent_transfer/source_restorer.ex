defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.SourceRestorer do
  @moduledoc false

  alias Vxpipe.CallEngine.{RoomTransferSupervisor, TextToSpeechRuntime}
  alias Vxpipe.CallEngine.RoomAuthority.{Startup, State}

  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.{
    Authorizer,
    History,
    Restoration
  }

  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @restoration_timeout_ms 750

  @spec start(Request.t(), GenServer.from(), History.failure_cause(), State.t()) ::
          :not_required | {:ok, Restoration.t()} | {:error, :unavailable}
  def start(%Request{} = request, from, cause, %State{} = state) do
    if restorable?(request, state) do
      start_worker(request, from, cause, state)
    else
      :not_required
    end
  end

  @spec activate(map(), Request.t(), State.t()) ::
          {:completed | :failed, State.t()}
  def activate(capability, %Request{} = request, %State{} = state) when is_map(capability) do
    if restorable?(request, state) do
      restored = Startup.activate_text_to_speech(capability)
      {:completed, %{state | text_to_speech_capability: restored}}
    else
      _ = Startup.discard_text_to_speech(capability, state)
      {:failed, state}
    end
  end

  defp start_worker(request, from, cause, state) do
    owner = Keyword.fetch!(state.agent_transfer_runtime.startup_options, :owner)

    case RoomTransferSupervisor.restore_text_to_speech(
           request.incarnation_id,
           state.text_to_speech_runtime,
           request.source_participant_id,
           owner
         ) do
      {:ok, task} ->
        timer =
          Process.send_after(
            self(),
            {:vxpipe_agent_transfer_restoration_deadline, task.ref},
            @restoration_timeout_ms
          )

        {:ok,
         %Restoration{
           cause: cause,
           from: from,
           request: request,
           task: task,
           timer: timer
         }}

      {:error, :unavailable} = error ->
        error
    end
  end

  defp restorable?(request, state) do
    match?(%TextToSpeechRuntime{}, state.text_to_speech_runtime) and
      is_nil(state.text_to_speech_capability) and
      Authorizer.authorize(request, state) == :ok
  end
end
