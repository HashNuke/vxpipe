defmodule Vxpipe.Providers.Deepgram.FixtureProcessIsolationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Deepgram.LiveFixture

  @moduletag :tmp_dir

  test "overlapping BEAM invocations keep private scratch files through another invocation's cleanup",
       %{
         tmp_dir: tmp_dir
       } do
    root = Path.join(tmp_dir, "checkout")
    global_tmp = Path.join(tmp_dir, "shared-system-temp")
    File.mkdir_p!(global_tmp)
    script = Path.join(tmp_dir, "fixture_probe.exs")

    File.write!(script, """
    [root] = System.argv()
    Vxpipe.Providers.Deepgram.LiveFixture.ensure!(
      root: root,
      request: fn -> {:ok, <<1, 0>>} end,
      transcode: fn pcm, opus ->
        IO.puts("ready:" <> pcm)
        "continue\\n" = IO.gets("")
        <<1, 0, _silence::binary>> = File.read!(pcm)
        File.write!(opus, "OggSfixture")
        :ok
      end
    )
    """)

    first = start_probe(script, root, global_tmp)
    first_pcm = await_ready(first)
    second = start_probe(script, root, global_tmp)
    second_pcm = await_ready(second)

    assert String.starts_with?(first_pcm, root <> "/")
    assert String.starts_with?(second_pcm, root <> "/")
    refute first_pcm == second_pcm
    assert File.regular?(first_pcm)
    assert File.regular?(second_pcm)

    assert Port.command(first, "continue\n")
    assert_receive {^first, {:exit_status, 0}}, 10_000
    refute File.exists?(Path.dirname(first_pcm))
    assert File.regular?(second_pcm)

    assert Port.command(second, "continue\n")
    assert_receive {^second, {:exit_status, 0}}, 10_000
    refute File.exists?(Path.dirname(second_pcm))
    assert File.read!(LiveFixture.opus_path(root)) == "OggSfixture"
  end

  defp start_probe(script, root, global_tmp) do
    executable = System.find_executable("elixir") |> String.to_charlist()
    ebin = LiveFixture |> :code.which() |> List.to_string() |> Path.dirname()

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        line: 8_192,
        args: ["--erl", "+S 1:1", "-pa", ebin, script, root],
        env: [{~c"TMPDIR", String.to_charlist(global_tmp)}]
      ])

    on_exit(fn ->
      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end)

    port
  end

  defp await_ready(port) do
    assert_receive {^port, {:data, {:eol, "ready:" <> path}}}, 10_000
    path
  end
end
