defmodule Vxpipe.CallEngine.SpeechTTSAdmissionProbe do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.TTSProvider

  @impl true
  def models, do: [Vxpipe.CallEngine.Speech.Model.new("test", "Test provider", true)]

  @impl true
  def configure(options), do: MorseSession.configure(options)
  @impl true
  def start_link(options), do: TTSProvider.start_link(__MODULE__, options)
  @impl true
  def speak(pid, reference, text), do: MorseSession.speak(pid, reference, text)
  @impl true
  def cancel(pid, reference, playback), do: MorseSession.cancel(pid, reference, playback)
  @impl true
  def close(pid), do: MorseSession.close(pid)

  @impl true
  def init(options) do
    private = Keyword.fetch!(options, :private)
    {:ok, state} = MorseSession.init(options)

    {:ok,
     Map.merge(state, %{
       observer: Keyword.fetch!(private, :observer),
       admission_mode: Keyword.get(private, :admission_mode, :accept)
     })}
  end

  @impl true
  def handle_call({:speak, reference, "E"} = message, from, state) do
    send(state.observer, {:tts_acceptance_held, reference})

    receive do
      :release_acceptance ->
        case state.admission_mode do
          :accept -> MorseSession.handle_call(message, from, state)
          :reject -> {:reply, {:error, :unsupported_character}, state}
        end
    after
      5_000 -> {:stop, :normal, {:error, :session_failed}, state}
    end
  end

  def handle_call(message, from, state), do: MorseSession.handle_call(message, from, state)

  @impl true
  def handle_info(message, state), do: MorseSession.handle_info(message, state)

  @impl true
  def format_status(status), do: MorseSession.format_status(status)
end
