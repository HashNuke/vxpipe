defmodule Vxpipe.Console.Test.LiveDiagnosticsBrowserSite do
  @moduledoc "Local fixture microphone endpoints around the existing production playground host."
  @behaviour Plug
  import Plug.Conn
  alias Vxpipe.Console.Test.StructuredBrowserSite

  @fixture Path.expand(
             "../../../vxpipe_call_engine/test/fixtures/speech/acoustic_acceptance/OSR_us_000_0010_8k.wav",
             __DIR__
           )
  def fixture_path, do: @fixture
  def init(options), do: options

  def call(%{method: "GET", request_path: "/__vad/microphone"} = conn, _options) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, "<!doctype html><html><body><button>Enable fixture</button></body></html>")
  end

  def call(%{method: "GET", request_path: "/__vad/fixture.wav"} = conn, _options),
    do: conn |> put_resp_content_type("audio/wav") |> send_file(200, @fixture)

  def call(%{method: "GET", request_path: "/__vad/status"} = conn, options) do
    status = Agent.get(options.progress, & &1)
    conn |> put_resp_content_type("application/json") |> send_resp(200, JSON.encode!(status))
  end

  def call(conn, options), do: StructuredBrowserSite.call(conn, options)
end
