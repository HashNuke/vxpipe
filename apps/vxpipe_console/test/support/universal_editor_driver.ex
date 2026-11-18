defmodule Vxpipe.Console.Test.UniversalEditorDriver do
  @moduledoc "Drives real editor save/publish controls in isolated headless Chrome."

  def build_assets(directory) do
    fixture = Path.expand("../fixtures/universal_editor.tsx", __DIR__)
    assets = Path.expand("../../assets", __DIR__)

    script = """
    require('esbuild').buildSync({entryPoints:[process.argv[1]],bundle:true,alias:{react:require('path').dirname(require.resolve('react/package.json')),'react-dom':require('path').dirname(require.resolve('react-dom/package.json'))},format:'esm',jsx:'automatic',outdir:process.argv[2],entryNames:'editor',assetNames:'[name]-[hash]',publicPath:'/__editor',loader:{'.woff2':'file','.woff':'file','.wav':'file'}});
    """

    case System.cmd("node", ["-e", script, fixture, directory],
           cd: assets,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _status} -> raise "editor asset build failed: #{output}"
    end
  end

  def run(url, provider_label) do
    session = "universal-editor-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    command = &command(session, &1)

    try do
      command.(["--args", "--no-sandbox", "open", url])
      command.(["set", "viewport", "1360", "900"])
      command.(["wait", "--text", provider_label])
      command.(["find", "role", "button", "click", "--name", "More actions", "--exact"])
      command.(["find", "role", "menuitem", "click", "--name", "Save as draft", "--exact"])
      command.(["wait", "--fn", "window.universalEditorSaved?.revision === 1"])

      command.([
        "wait",
        "--fn",
        "Array.from(document.querySelectorAll('button')).some(button => button.textContent.trim() === 'Publish' && !button.disabled && !button.closest('[aria-hidden=true]'))"
      ])

      command.(["find", "role", "button", "click", "--name", "Publish", "--exact"])
      command.(["wait", "--fn", "window.universalEditorSaved?.publishedRevision === 1"])
      desktop = Path.join(System.tmp_dir!(), session <> "-desktop.png")
      command.(["screenshot", desktop])
      command.(["set", "viewport", "390", "844"])
      command.(["find", "role", "button", "click", "--name", "Call settings", "--exact"])

      command.([
        "wait",
        "--fn",
        "document.querySelector('[role=dialog]')?.getBoundingClientRect().x === 0"
      ])

      phone = Path.join(System.tmp_dir!(), session <> "-phone.png")
      command.(["screenshot", phone])
      saved = command.(["eval", "window.universalEditorSaved"])
      Map.put(saved, "screenshots", %{"desktop" => desktop, "phone" => phone})
    rescue
      error ->
        path = Path.join(System.tmp_dir!(), session <> "-failure.png")
        command.(["screenshot", path])
        IO.puts("UNIVERSAL_EDITOR_ERRORS " <> inspect(command.(["errors"])))

        reraise RuntimeError,
                [message: Exception.message(error) <> "; screenshot: " <> path],
                __STACKTRACE__
    after
      command.(["close"])
    end
  end

  defp command(session, arguments) do
    browser = System.find_executable("agent-browser") || raise "agent-browser is required"
    setsid = System.find_executable("setsid") || raise "setsid is required"

    {output, status} =
      System.cmd(setsid, ["--wait", browser, "--session", session, "--json" | arguments],
        stderr_to_stdout: true,
        env: [{"AGENT_BROWSER_DEFAULT_TIMEOUT", "30000"}]
      )

    case {status, JSON.decode(output)} do
      {0, {:ok, %{"success" => true, "data" => data}}} -> Map.get(data, "result", data)
      _failed -> raise "editor Chrome #{hd(arguments)} failed: #{output}"
    end
  end
end
