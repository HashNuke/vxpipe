defmodule Vxpipe.CallEngine.SpeechExperiment.TTSBridge do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech.Transport
  alias Vxpipe.CallEngine.SpeechExperiment.Scope

  def start_link(options) do
    settings = Keyword.fetch!(options, :transport_options)
    %{config: config} = Keyword.fetch!(options, :connection)
    arguments = [owner: Keyword.fetch!(options, :owner), kind: :tts, config: config] ++ settings

    with {:ok, control} <- Scope.start_session(Keyword.fetch!(settings, :scope), arguments) do
      Process.link(control)
      {:ok, control}
    end
  end

  def send_control(control, payload), do: GenServer.call(control, {:control, payload}, 5_000)
  def close(control), do: GenServer.call(control, :close, 5_000)
end
