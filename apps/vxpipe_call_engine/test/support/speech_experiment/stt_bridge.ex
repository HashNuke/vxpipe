defmodule Vxpipe.CallEngine.SpeechExperiment.STTBridge do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Provider.SpeechToText.Transport
  alias Vxpipe.CallEngine.SpeechExperiment.Scope

  def start_link(options) do
    settings = Keyword.fetch!(options, :transport_options)
    %{config: config} = Keyword.fetch!(options, :connection)
    arguments = [owner: Keyword.fetch!(options, :owner), kind: :stt, config: config] ++ settings

    with {:ok, control} <- Scope.start_session(Keyword.fetch!(settings, :scope), arguments) do
      Process.link(control)
      {:ok, control}
    end
  end

  def send_audio(control, audio), do: GenServer.call(control, {:audio, audio}, 5_000)
  def close(control), do: GenServer.call(control, :close, 5_000)
end
