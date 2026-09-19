defmodule Vxpipe.CallEngine.SpeechExperiment.TTSMeter do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech.Transport
  @registry Vxpipe.CallEngine.RoomRegistry

  def start_link(options) do
    settings = Keyword.fetch!(options, :transport_options)
    {module, transport_options} = Keyword.fetch!(settings, :delegate)
    observer = Keyword.fetch!(settings, :observer)

    with {:ok, transport} <-
           module.start_link(Keyword.put(options, :transport_options, transport_options)) do
      {:ok, _} = Registry.register(@registry, {__MODULE__, transport}, {module, observer})
      {:ok, transport}
    end
  end

  def send_control(transport, payload) do
    [{_, {module, observer}}] = Registry.lookup(@registry, {__MODULE__, transport})

    case JSON.decode!(payload) do
      %{"type" => "Speak"} ->
        send(observer, {:experiment_text_received, System.monotonic_time(:microsecond)})

      _ ->
        :ok
    end

    module.send_control(transport, payload)
  end

  def close(transport) do
    [{_, {module, _}}] = Registry.lookup(@registry, {__MODULE__, transport})
    module.close(transport)
  end
end
