defmodule Vxpipe.Console.Integration.MorseCodeApiOriginRestartTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :morse_code_api_restart
  @moduletag timeout: 240_000

  @tag :tmp_dir
  test "persisted Morse rooms survive origin cutover and retire recognition on service outage",
       %{tmp_dir: directory} do
    root = Path.expand("../../../..", __DIR__)
    fixture = Path.join(root, "apps/vxpipe_console/test/fixtures/morse_origin_proxy.go")
    executable = Path.join(directory, "morse-origin-proxy")
    binary = System.fetch_env!("MORSE_CODE_API_TEST_BINARY") |> Path.expand()
    assert File.regular?(binary)

    {output, status} =
      System.cmd("go", ["build", "-o", executable, fixture], stderr_to_stdout: true)

    assert status == 0, output

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        {:line, 4096},
        args: [binary, directory]
      ])

    try do
      assert_receive {^port, {:data, {:eol, ready}}}, 35_000

      assert %{"event" => "ready", "plain" => plain, "secure" => secure, "ca" => ca} =
               Jason.decode!(ready)

      database =
        "vxpipe_morse_restart_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      env = [
        {"MIX_ENV", "test"},
        {"VXPIPE_TEST_DATABASE_URL", nil},
        {"VXPIPE_TEST_DATABASE", database}
      ]

      output = mix(root, env, ["ecto.create", "--no-compile"])
      assert output =~ "has been created"

      on_exit(fn ->
        # This name was generated and successfully created by this test only.
        mix(root, env, ["ecto.drop", "--no-compile", "--force", "--quiet"])
      end)

      mix(root, env, ["ecto.migrate", "--no-compile", "--quiet"])
      path = Path.join(directory, "publication.json")
      probe = "apps/vxpipe_console/test/fixtures/morse_restart_probe.exs"
      seed = ["run", "--no-compile", probe, "seed", path, "none"]

      assert mix(root, env ++ [{"MORSE_CODE_API_BASE_URL", plain}], seed) =~
               "Morse restart fixture persisted"

      snapshot = File.read!(path)

      for {origin, label, trust} <- [
            {plain, "plain", "none"},
            {secure, "secure", ca},
            {plain, "plain", "none"}
          ] do
        if label == "secure" do
          reject = ["run", "--no-compile", probe, "reject_tls", path, "none"]

          assert mix(root, env ++ [{"MORSE_CODE_API_BASE_URL", origin}], reject) =~
                   "Morse untrusted HTTPS and WSS rejected"

          assert observations(port) == []
        end

        run = ["run", "--no-compile", probe, "room", path, trust]

        assert mix(root, env ++ [{"MORSE_CODE_API_BASE_URL", origin}], run) =~
                 "Morse persisted service and room verified"

        assert File.read!(path) == snapshot
        requests = observations(port)
        assert Enum.all?(requests, &(&1["origin"] == label))

        # Session preparation may open more than one allocation. Every observed
        # request must use the selected origin and an expected speech/probe route.
        assert requests |> Enum.map(&{&1["method"], &1["path"]}) |> Enum.uniq() |> Enum.sort() ==
                 [
                   {"GET", "/v1/models"},
                   {"GET", "/v1/speech-to-text/realtime"},
                   {"GET", "/v1/voices"},
                   {"POST", "/v1/text-to-speech/morse/stream"}
                 ]
      end

      outage = ["run", "--no-compile", probe, "outage", path, "none"]

      assert mix(root, env ++ [{"MORSE_CODE_API_BASE_URL", plain}], outage) =~
               "Morse outage retired recognition without publishing a final or reply"

      assert File.read!(path) == snapshot
      requests = observations(port)
      assert Enum.all?(requests, &(&1["origin"] == "plain"))

      assert requests |> Enum.map(&{&1["method"], &1["path"]}) |> Enum.uniq() |> Enum.sort() ==
               [
                 {"GET", "/v1/models"},
                 {"GET", "/v1/speech-to-text/realtime"},
                 {"GET", "/v1/voices"},
                 {"POST", "/__fixture/stop"}
               ]
    after
      if Port.info(port) do
        Port.command(port, "stop\n")
        assert_receive {^port, {:exit_status, 0}}, 20_000
      end
    end
  end

  defp observations(port) do
    Port.command(port, "barrier\n")
    collect(port, [])
  end

  defp collect(port, requests) do
    assert_receive {^port, {:data, {:eol, line}}}, 5_000

    case Jason.decode!(line) do
      %{"event" => "barrier"} -> Enum.reverse(requests)
      %{"event" => "root_probe"} -> collect(port, requests)
      %{"event" => "request"} = request -> collect(port, [request | requests])
    end
  end

  defp mix(root, env, args) do
    {output, status} = System.cmd("mix", args, cd: root, env: env, stderr_to_stdout: true)
    assert status == 0, "fresh Vxpipe process failed:\n#{output}"
    output
  end
end
