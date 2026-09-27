defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.HistoryBarrier do
  @moduledoc "Orders room publication acknowledgments before provider reseeding."

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output
  alias Vxpipe.CallEngine.Speech.{Channel, Session}

  def published(
        %{owner: owner, descriptor: %{continuity: :history_reseed}} = state,
        owner,
        {role, text} = entry
      )
      when role in [:caller, :agent] and is_binary(text) and text != "" do
    case Session.append_history(state.session, entry) do
      :ok -> {:noreply, state}
      _failure -> Output.stop_unavailable(:provider_failed, state)
    end
  end

  def published(state, _owner, _entry), do: {:noreply, state}

  def channel(
        %{session: session, descriptor: %{continuity: :history_reseed}} = state,
        channel,
        provider,
        reference
      )
      when is_pid(channel) and is_pid(provider) and is_reference(reference) do
    if channel == GenServer.whereis(Channel.address(session)) and
         provider == Session.provider(session) do
      if state.room_history_barrier? do
        send(state.owner, {:vxpipe_sts_reseed_room_barrier, self(), reference})
        {:noreply, %{state | pending_reseed_barrier: {provider, reference}}}
      else
        send(provider, {:vxpipe_sts_reseed_history_ready, self(), reference})
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def channel(state, _channel, _provider, _reference), do: {:noreply, state}

  def room(
        %{owner: owner, pending_reseed_barrier: {provider, reference}} = state,
        owner,
        reference
      ) do
    if provider == Session.provider(state.session) do
      send(provider, {:vxpipe_sts_reseed_history_ready, self(), reference})
    end

    {:noreply, %{state | pending_reseed_barrier: nil}}
  end

  def room(state, _owner, _reference), do: {:noreply, state}
end
