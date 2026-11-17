defmodule Vxpipe.Console.Test.StructuredBrowserDriver do
  @moduledoc "Drives the production playground in headless Chrome for tagged provider acceptance."

  @launch_args Enum.join(
                 [
                   "--no-sandbox",
                   "--use-fake-device-for-media-stream",
                   "--use-fake-ui-for-media-stream",
                   "--autoplay-policy=no-user-gesture-required",
                   "--disable-features=WebRtcHideLocalIpsWithMdns"
                 ],
                 ","
               )

  def run(url) do
    browser = System.find_executable("agent-browser") || raise "agent-browser is required"
    session = "structured-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    command = &command(browser, session, &1)

    try do
      command.(["--args", @launch_args, "open", url])
      command.(["set", "viewport", "1360", "900"])
      probe = File.read!(Path.expand("../fixtures/structured_browser_probe.js", __DIR__))
      command.(["eval", probe])
      command.(["find", "role", "button", "click", "--name", "Create room", "--exact"])
      IO.puts("structured_browser_driver preparing")

      command.([
        "eval",
        "(async()=>await new Promise((resolve,reject)=>{const deadline=performance.now()+20000; const poll=()=>Array.from(document.querySelectorAll('button')).some(b=>b.textContent.trim()==='Connect')?resolve(true):performance.now()>deadline?reject(new Error('Call preparation timeout')):setTimeout(poll,50);poll();}))()"
      ])

      command.([
        "eval",
        "(async()=>await new Promise((resolve,reject)=>{const deadline=performance.now()+20000; const poll=()=>Array.from(document.querySelectorAll('dt')).find(e=>e.textContent.trim()==='Client')?.nextElementSibling?.textContent.trim().toLowerCase()==='initialized'?resolve(true):performance.now()>deadline?reject(new Error('RTVI initialization timeout')):setTimeout(poll,50);poll();}))()"
      ])

      IO.puts("structured_browser_driver connecting")
      command.(["find", "role", "button", "click", "--name", "Connect", "--exact"])

      command.([
        "eval",
        "(async()=>await new Promise((resolve,reject)=>{const deadline=performance.now()+20000; const poll=()=>structuredProbe.channels.some(c=>c.readyState==='open') && structuredProbe.events.some(e=>e.type==='bot-ready')?resolve(true):performance.now()>deadline?reject(new Error('RTVI ready timeout')):setTimeout(poll,50);poll();}))()"
      ])

      IO.puts("structured_browser_driver connected")

      for label <- ["SHORT", "LONG", "QUIET", "LOOKUP", "MATH"] do
        send_input(command, label)
        wait_for_response(command)
        IO.puts("structured_browser_case " <> label)
      end

      command.([
        "eval",
        "(async()=>{structuredProbe.begin('TOOL_COMPLETION'); await fetch('/__structured/control',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:'release_tool'})}); return true;})()"
      ])

      wait_for_response(command)
      send_input(command, "SHORT")
      wait_for_response(command)

      for label <- ["IDLE_SPOKEN", "IDLE_SILENT"] do
        send_input(command, label)
        wait_for_response(command)
        command.(["eval", "structuredProbe.begin(#{JSON.encode!(label <> "_TIMEOUT")})"])
        wait_for_response(command)
        IO.puts("structured_browser_case " <> label <> "_TIMEOUT")
      end

      command.(["set", "viewport", "1360", "900"])
      desktop = Path.join(System.tmp_dir!(), "vxpipe-#{session}-desktop.png")
      command.(["screenshot", desktop])
      command.(["set", "viewport", "390", "844"])

      command.([
        "eval",
        "(()=>{const tab=Array.from(document.querySelectorAll('[role=tab]')).find(e=>e.getClientRects().length && e.textContent.trim()==='' && e.getAttribute('aria-controls')?.endsWith('-content-conversation'));if(!tab)throw new Error('Mobile conversation tab missing');tab.dataset.structuredMobileConversation='true';return true;})()"
      ])

      command.(["focus", "[data-structured-mobile-conversation=true]"])
      command.(["press", "Enter"])

      command.([
        "eval",
        "(async()=>await new Promise((resolve,reject)=>{const deadline=performance.now()+5000;const poll=()=>{const input=Array.from(document.querySelectorAll('[placeholder=\"Type message...\"]')).find(e=>e.getClientRects().length);if(input)return resolve(true);if(performance.now()>deadline)return reject(new Error('Phone conversation panel missing'));setTimeout(poll,50);};poll();}))()"
      ])

      phone = Path.join(System.tmp_dir!(), "vxpipe-#{session}-phone.png")
      command.(["screenshot", phone])
      evidence = command.(["eval", "(async()=>await structuredProbe.evidence())()"])
      Map.put(evidence, "screenshots", %{"desktop" => desktop, "phone" => phone})
    rescue
      error ->
        screenshot = Path.join(System.tmp_dir!(), "vxpipe-#{session}-failure.png")
        command.(["screenshot", screenshot])

        diagnostic =
          command.([
            "eval",
            "({buttons:Array.from(document.querySelectorAll('button')).map(b=>b.textContent.trim()),tabs:Array.from(document.querySelectorAll('[role=tab]')).map(e=>({id:e.id,text:e.textContent.trim(),visible:!!e.getClientRects().length,controls:e.getAttribute('aria-controls')})),alert:document.querySelector('[role=alert]')?.textContent,peers:structuredProbe.peers.map(p=>({connection:p.connectionState,signaling:p.signalingState})),channels:structuredProbe.channels.map(c=>c.readyState),requests:structuredProbe.requests,clicks:structuredProbe.clicks,errors:structuredProbe.errors,cases:structuredProbe.cases.map(({text,error,output})=>({text,error,output}))})"
          ])

        IO.puts(
          "structured_browser_failure " <>
            JSON.encode!(Map.put(diagnostic, "screenshot", screenshot))
        )

        reraise error, __STACKTRACE__
    after
      command.(["close"])
    end
  end

  defp send_input(command, label) do
    command.(["eval", "structuredProbe.begin(#{JSON.encode!(label)})"])
    command.(["find", "placeholder", "Type message...", "fill", label])
    command.(["press", "Enter"])
  end

  defp wait_for_response(command) do
    command.([
      "wait",
      "--fn",
      """
      (()=>{
        const item=structuredProbe.cases.at(-1);
        return !!item.error || !!(item.completedAt && performance.now()-item.completedAt>500 && performance.now()-structuredProbe.lastSpeechAt>500);
      })()
      """
    ])

    command.([
      "eval",
      "(()=>{const item=structuredProbe.cases.at(-1);if(item.error)throw new Error('Agent response failed for '+item.text);return true;})()"
    ])
  end

  defp command(browser, session, arguments) do
    setsid = System.find_executable("setsid") || raise "setsid is required for browser isolation"

    {output, status} =
      System.cmd(setsid, ["--wait", browser, "--session", session, "--json" | arguments],
        stderr_to_stdout: true,
        env: [{"AGENT_BROWSER_DEFAULT_TIMEOUT", "60000"}]
      )

    case {status, JSON.decode(output)} do
      {0, {:ok, %{"success" => true, "data" => data}}} -> Map.get(data, "result", data)
      _failed -> raise "Chrome command #{hd(arguments)} failed: #{output}"
    end
  end
end
