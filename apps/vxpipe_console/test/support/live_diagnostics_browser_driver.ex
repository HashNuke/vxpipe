defmodule Vxpipe.Console.Test.LiveDiagnosticsBrowserDriver do
  @moduledoc "Real Chrome fixture microphone and production UI driver; no provider emulation."
  import ExUnit.Callbacks
  alias Vxpipe.Console.Test.LiveDiagnosticsBrowserSite

  @args "--no-sandbox,--use-fake-device-for-media-stream,--use-fake-ui-for-media-stream,--autoplay-policy=no-user-gesture-required,--disable-features=WebRtcHideLocalIpsWithMdns"
  @probe Path.expand("../fixtures/live_diagnostics_microphone.js", __DIR__)

  def verify_microphone! do
    server =
      start_supervised!(
        {Bandit, plug: {LiveDiagnosticsBrowserSite, %{}}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    with_browser(fn command ->
      command.(["--args", @args, "open", "http://127.0.0.1:#{port}/__vad/microphone"])
      command.(["eval", File.read!(@probe)])

      command.([
        "eval",
        """
        (async()=>{
          const first=await navigator.mediaDevices.getUserMedia({audio:true});
          const second=await navigator.mediaDevices.getUserMedia({audio:true});
          const sender=new RTCPeerConnection(), receiver=new RTCPeerConnection();
          sender.onicecandidate=e=>e.candidate&&receiver.addIceCandidate(e.candidate);
          receiver.onicecandidate=e=>e.candidate&&sender.addIceCandidate(e.candidate);
          sender.addTrack(first.getAudioTracks()[0],first);
          try {
            await sender.setLocalDescription(await sender.createOffer());
            await receiver.setRemoteDescription(sender.localDescription);
            await receiver.setLocalDescription(await receiver.createAnswer());
            await sender.setRemoteDescription(receiver.localDescription);
            const e=await vadProbe.play();
            const duration=async()=>Array.from((await sender.getStats()).values()).find(s=>s.type==='media-source'&&s.kind==='audio')?.totalSamplesDuration||0;
            const before=await duration();
            await new Promise(resolve=>setTimeout(resolve,400));
            return {...e,silence_duration:(await duration())-before,same_track:first.getAudioTracks()[0]===second.getAudioTracks()[0]};
          } finally {sender.close();receiver.close();}
        })()
        """
      ])
    end)
  end

  def run!(origin, email, password, session, check_artifact) do
    with_browser(
      fn command ->
        command.(["--args", @args, "open", origin <> "/admin/samples/pipecat-console"])
        command.(["set", "viewport", "1440", "1000"])
        command.(["eval", File.read!(@probe)])
        command.(["find", "role", "button", "click", "--name", "Create room", "--exact"])

        wait(
          command,
          "Array.from(document.querySelectorAll('button')).some(b=>b.textContent.trim()==='Connect')"
        )

        wait(
          command,
          "Array.from(document.querySelectorAll('dt')).find(e=>e.textContent.trim()==='Client')?.nextElementSibling?.textContent.trim().toLowerCase()==='initialized'"
        )

        command.(["find", "role", "button", "click", "--name", "Connect", "--exact"])

        wait(
          command,
          "vadProbe.channels.some(c=>c.readyState==='open') && vadProbe.events.some(e=>e.type==='bot-ready')"
        )

        for {phase, pause} <- [{"normal", 0}, {"pause", 180}] do
          phase(command, phase)
          command.(["eval", "vadProbe.play({pauseMs:#{pause}})"])
          wait_phase(command, phase)
        end

        phase(command, "barge_base")
        command.(["eval", "vadProbe.bargeMarker=performance.now();vadProbe.play()"])

        wait(
          command,
          "vadProbe.events.some(e=>e.type==='bot-started-speaking' && e.at>vadProbe.bargeMarker && performance.now()-e.at>=1000 && !vadProbe.events.some(stop=>stop.type==='bot-stopped-speaking' && stop.at>e.at))"
        )

        phase(command, "barge")
        command.(["eval", "vadProbe.play()"])
        wait_phase(command, "barge")
        phase(command, "tool")
        command.(["eval", "vadProbe.play()"])
        wait_phase(command, "tool")

        media =
          command.([
            "eval",
            "({plays:vadProbe.plays,rtvi:vadProbe.events.map(e=>({id:e.id,type:e.type,at:e.at})),connected:vadProbe.peers.some(p=>p.connectionState==='connected')})"
          ])

        unless media["connected"],
          do: raise("Fixture did not use a connected browser WebRTC peer")

        call =
          command.(["eval", "(async()=> (await(await fetch('/__vad/status')).json()).call)()"])

        command.(["find", "role", "button", "click", "--name", "Disconnect", "--exact"])
        wait(command, "!vadProbe.peers.some(p=>p.connectionState==='connected')")

        command.([
          "eval",
          "fetch('/__structured/control',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:'hangup'})}).then(r=>r.json())"
        ])

        wait_async(
          command,
          "(async()=> (await(await fetch('/__vad/status')).json()).hung_up===true)()"
        )

        hung_up =
          command.([
            "eval",
            "(async()=> (await(await fetch('/__vad/status')).json()).hung_up===true)()"
          ])

        IO.puts("LIVE_DIAGNOSTICS_STAGE admin_inspection")
        command.(["open", origin <> "/auth/login"])
        command.(["find", "label", "Email", "fill", email])
        command.(["find", "label", "Password", "fill", password])
        command.(["find", "role", "button", "click", "--name", "Sign in", "--exact"])
        wait(command, "!location.pathname.startsWith('/auth/')")
        path = "/admin/tenants/#{call["tenant_key"]}/calls/#{call["id"]}"
        api = "/api/tenants/#{call["tenant_key"]}/calls/#{call["id"]}/latency"
        command.(["open", origin <> path])

        wait(
          command,
          "document.querySelector('button[aria-label=\"Show Technical events\"]')?.getAttribute('aria-pressed')==='false'"
        )

        hidden_count =
          command.(["eval", "document.querySelectorAll('.vx-timeline-activity').length"])

        command.([
          "find",
          "role",
          "button",
          "click",
          "--name",
          "Show Technical events",
          "--exact"
        ])

        wait(
          command,
          "document.querySelector('button[aria-label=\"Hide Technical events\"]')?.getAttribute('aria-pressed')==='true' && document.querySelectorAll('.vx-timeline-activity').length>#{hidden_count}"
        )

        command.([
          "find",
          "role",
          "button",
          "click",
          "--name",
          "Hide Technical events",
          "--exact"
        ])

        wait(
          command,
          "document.querySelectorAll('.vx-timeline-activity').length===#{hidden_count}"
        )

        command.(["find", "role", "button", "click", "--name", "Metrics", "--exact"])
        command.(["find", "role", "button", "click", "--name", "Latency diagnostics", "--exact"])
        IO.puts("LIVE_DIAGNOSTICS_STAGE admin_latency_open")

        summary =
          command.([
            "eval",
            "(async()=>{const response=await fetch(#{JSON.encode!(api)});const report=await response.json();return {status:response.status,run_count:report.runs?.length,unavailable_reason:report.unavailable_reason,error:report.error};})()"
          ])

        IO.puts("LIVE_DIAGNOSTICS_API " <> JSON.encode!(summary))
        wait(command, "!!document.querySelector('table[aria-label=\"Per-turn latency\"]')")

        report =
          command.([
            "eval",
            """
            (async()=>{
              const endpoint=#{JSON.encode!(api)};
              const deadline=performance.now()+30000;
              while(performance.now()<deadline){
                const response=await fetch(endpoint,{cache:'no-store'});
                if(!response.ok)throw new Error('Authorized diagnostic read failed');
                const report=await response.json();
                if(report.runs.length===1 && report.runs[0].closed_at){
                  const turns=await(await fetch(endpoint+'/runs/'+report.runs[0].id+'/turns',{cache:'no-store'})).json();
                  return {report,turns};
                }
                await new Promise(resolve=>setTimeout(resolve,100));
              }
              throw new Error('Persisted diagnostic run did not close after hangup');
            })()
            """
          ])

        check_artifact.(report)
        command.(["find", "role", "button", "click", "--name", "Refresh diagnostics", "--exact"])

        wait(
          command,
          "document.querySelectorAll('table[aria-label=\"Per-turn latency\"] > tbody > tr > th small[title]').length===#{length(report["turns"]["turns"])}"
        )

        text =
          command.([
            "eval",
            "document.querySelector('table[aria-label=\"Per-turn latency\"]').textContent"
          ])

        unless String.contains?(text, "End-of-turn detection") and
                 String.contains?(text, "Barge-in stop delay"),
               do: raise("Production admin UI did not render both primary measurements")

        displayed =
          command.([
            "eval",
            """
            (async()=>{
              const rows=#{JSON.encode!(report["turns"]["turns"])};
              const table=document.querySelector('table[aria-label="Per-turn latency"]');
              const ms=value=>value==null?'Unavailable':Math.round(value/1000).toLocaleString()+' ms';
              const bargeMs=value=>value>0&&value<1000?'<1 ms':ms(value);
              const firstText=cell=>Array.from(cell.childNodes).filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent).join('').trim();
              const waitFor=async f=>{const until=performance.now()+5000;while(!f()){if(performance.now()>until)throw new Error('Evidence row did not expand');await new Promise(requestAnimationFrame);}};
              for(const row of rows){
                const tr=Array.from(table.tBodies[0].rows).find(tr=>tr.querySelector(':scope>th small[title]')?.title===row.turn_id);
                if(!tr)throw new Error('Missing canonical turn in production UI');
                const cells=tr.querySelectorAll(':scope>td');
                if(cells[0].textContent.trim()!==ms(row.durations_us.speech_end_to_provider_end))throw new Error('Endpoint value in wrong row or column');
                if(row.durations_us.speech_end_to_provider_end==null && cells[0].title!==row.metric_reasons.speech_end_to_provider_end.replaceAll('_',' '))throw new Error('Endpoint unavailable reason missing');
                const entries=row.barge_in?.entries??[];
                const values=entries.map(e=>e.duration_us).filter(Number.isFinite).sort((a,b)=>a-b);
                const median=values.length?(values[Math.floor((values.length-1)/2)]+values[Math.floor(values.length/2)])/2:null;
                const expected=!row.barge_in?'Unavailable':!entries.length?'No interruption recorded':bargeMs(median)+(entries.length>1&&median!==null?' median':'');
                if(firstText(cells[1])!==expected)throw new Error('Barge value in wrong row or column');
                if(!row.barge_in && !cells[1].textContent.includes('not recorded'))throw new Error('Barge unavailable reason missing');
                const toggle=tr.querySelector('button[aria-controls]');toggle.click();
                await waitFor(()=>document.getElementById(toggle.getAttribute('aria-controls')));
                const detail=document.getElementById(toggle.getAttribute('aria-controls'));
                for(const entry of entries){
                  const sub=Array.from(detail.querySelectorAll('table[aria-label="Barge-in measurements"] tbody tr')).find(tr=>tr.querySelector('th small[title]')?.title===entry.output_id);
                  if(!sub)throw new Error('Interrupted output identity missing');
                  const timing=sub.querySelectorAll(':scope>td');
                  if(firstText(timing[0])!==bargeMs(entry.speech_started_us)||firstText(timing[1])!==bargeMs(entry.playback_stopped_us)||firstText(timing[2])!==bargeMs(entry.duration_us))throw new Error('Interrupted output timings differ');
                  if(!sub.textContent.includes(entry.response_turn_id)||!sub.textContent.includes(entry.output_connection_id))throw new Error('Interrupted source identities differ');
                  if(!entry.reasons.every(reason=>sub.textContent.includes(reason.replaceAll('_',' '))))throw new Error('Barge unavailable reasons differ');
                }
              }
              return rows.length>0;
            })()
            """
          ])

        unless displayed,
          do: raise("Production admin values differ from persisted primary timings")

        screenshot = Path.join(System.tmp_dir!(), "vxpipe-live-diagnostics-#{call["id"]}.png")
        command.(["screenshot", screenshot])

        %{
          "pause_resume" =>
            Enum.any?(media["plays"], &(&1["pause_frames"] == 1440 and &1["ended"] == true)),
          "technical_events_inspected" => true,
          "hung_up" => hung_up,
          "admin_ui_inspected" => true,
          "media" => media,
          "stored" => report,
          "rendered" => text,
          "screenshot" => screenshot
        }
      end,
      session
    )
  end

  defp phase(command, phase),
    do:
      command.([
        "eval",
        "fetch('/__structured/control',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:'phase',phase:#{JSON.encode!(phase)}})}).then(r=>r.json())"
      ])

  defp wait_phase(command, phase),
    do:
      wait_async(
        command,
        "(async()=> (await(await fetch('/__vad/status')).json()).finished.includes(#{JSON.encode!(phase)}))()"
      )

  defp wait_async(command, expression) do
    command.([
      "eval",
      "(async()=>{const deadline=Date.now()+40000;while(!(await (#{expression}))){if(Date.now()>=deadline)throw new Error('Fixture predicate timed out');await new Promise(resolve=>setTimeout(resolve,100));}return true;})()"
    ])
  end

  defp wait(command, expression), do: command.(["wait", "--fn", expression])

  def session, do: "vad-live-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  def close(session) do
    browser = System.find_executable("agent-browser") || raise "agent-browser required"
    command(browser, session, ["close"])
  end

  def with_browser(fun, session \\ session()) do
    browser = System.find_executable("agent-browser") || raise "agent-browser required"
    command = &command(browser, session, &1)

    try do
      fun.(command)
    rescue
      error ->
        evidence =
          command.([
            "eval",
            "(async()=>({path:location.pathname,latency:document.querySelector('.vx-latency-body')?.textContent,events:window.vadProbe?.events.map(e=>({type:e.type,at:e.at})),peers:window.vadProbe?.peers.map(p=>p.connectionState),bargeMarker:window.vadProbe?.bargeMarker,stats:await Promise.all((window.vadProbe?.peers||[]).map(async p=>Array.from((await p.getStats()).values()).filter(s=>s.type==='media-source'||s.type==='outbound-rtp').map(s=>({type:s.type,kind:s.kind,packetsSent:s.packetsSent,bytesSent:s.bytesSent,totalAudioEnergy:s.totalAudioEnergy,totalSamplesDuration:s.totalSamplesDuration}))))}))()"
          ])

        IO.puts("LIVE_DIAGNOSTICS_BROWSER_FAILURE " <> JSON.encode!(evidence))
        reraise error, __STACKTRACE__
    after
      command.(["close"])
    end
  end

  defp command(browser, session, arguments) do
    setsid = System.find_executable("setsid") || raise "setsid required"

    {output, status} =
      System.cmd(setsid, ["--wait", browser, "--session", session, "--json" | arguments],
        stderr_to_stdout: true,
        env: [{"AGENT_BROWSER_DEFAULT_TIMEOUT", "45000"}]
      )

    case {status, JSON.decode(output)} do
      {0, {:ok, %{"success" => true, "data" => data}}} -> Map.get(data, "result", data)
      _ -> raise "Fixture browser command #{hd(arguments)} failed: #{output}"
    end
  end
end
