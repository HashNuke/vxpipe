defmodule Vxpipe.CallEngine.DeepgramAudioConfirmationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.TestDeepgramAudioConfirmation

  test "finite confirmation sends the captured PCM with its real format and no wording hints" do
    pcm = <<1::little-signed-16, 2::little-signed-16>>

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/listen"
      conn = Plug.Conn.fetch_query_params(conn)

      assert conn.query_params == %{
               "model" => "nova-3",
               "encoding" => "linear16",
               "sample_rate" => "24000",
               "channels" => "1",
               "language" => "en"
             }

      assert Plug.Conn.get_req_header(conn, "authorization") == ["Token synthetic-key"]
      assert {:ok, ^pcm, conn} = Plug.Conn.read_body(conn)
      Req.Test.json(conn, response("Alpha."))
    end)

    assert {:ok, "Alpha."} = confirm(pcm)
  end

  for {status, body} <- [
        {200, %{}},
        {200, %{"results" => %{"channels" => []}}},
        {401, %{}},
        {200, %{"results" => %{"channels" => [%{"alternatives" => [%{"transcript" => ""}]}]}}}
      ] do
    test "finite confirmation rejects unavailable recognition #{status}: #{inspect(body)}" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(unquote(status))
        |> Req.Test.json(unquote(Macro.escape(body)))
      end)

      assert {:error, :recognition_failed} = confirm(<<0, 0>>)
    end
  end

  defp confirm(pcm) do
    TestDeepgramAudioConfirmation.transcribe(pcm, 24_000, "synthetic-key",
      timeout_ms: 1_000,
      plug: {Req.Test, __MODULE__}
    )
  end

  defp response(text) do
    %{"results" => %{"channels" => [%{"alternatives" => [%{"transcript" => text}]}]}}
  end
end
