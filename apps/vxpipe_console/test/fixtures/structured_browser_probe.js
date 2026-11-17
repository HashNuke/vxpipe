(() => {
  const probe = { peers: [], channels: [], events: [], cases: [], requests: [], clicks: [], errors: [], speechFrames: 0, lastSpeechAt: 0 };
  window.structuredProbe = probe;
  const originalError = console.error.bind(console);
  console.error = (...items) => {
    probe.errors.push(items.map(item => item instanceof Error ? {name: item.name, message: item.message} : typeof item === "string" ? item : "[object]"));
    originalError(...items);
  };
  document.addEventListener("click", event => {
    const button = event.target.closest("button");
    if (button) probe.clicks.push(button.textContent.trim());
  });
  const originalFetch = window.fetch.bind(window);
  window.fetch = async (input, options) => {
    const url = new URL(typeof input === "string" || input instanceof URL ? input : input.url, location.href);
    const record = {origin: url.origin, path: url.pathname, method: options?.method ?? "GET"};
    probe.requests.push(record);
    const response = await originalFetch(input, options);
    record.status = response.status;
    record.contentType = response.headers.get("content-type");
    return response;
  };
  const BasePeer = window.RTCPeerConnection;

  function observeChannel(channel) {
    probe.channels.push(channel);
    const send = channel.send.bind(channel);
    channel.send = payload => {
      try {
        const message = JSON.parse(payload);
        const current = probe.cases.at(-1);
        if (current && message.type === "send-text") current.sentAt = performance.now();
      } catch { /* Preserve unrelated channel traffic. */ }
      return send(payload);
    };
    channel.addEventListener("message", event => {
      try {
        const message = JSON.parse(event.data);
        probe.events.push({ at: performance.now(), ...message });
        const current = probe.cases.at(-1);
        if (current && message.type === "bot-output" && message.data.spoken_status === "new") {
          current.outputAt ??= performance.now();
          current.output.push(message.data.text);
        }
        if (current && message.type === "bot-stopped-speaking") current.completedAt = performance.now();
        if (current && message.type === "error-response") current.error = message.data;
      } catch { /* Non-RTVI transport messages are outside this probe. */ }
    });
  }

  window.RTCPeerConnection = new Proxy(BasePeer, {
    construct(Target, args) {
      const peer = Reflect.construct(Target, args);
      probe.peers.push(peer);
      const createChannel = peer.createDataChannel.bind(peer);
      peer.createDataChannel = (...parameters) => {
        const channel = createChannel(...parameters);
        observeChannel(channel);
        return channel;
      };
      peer.addEventListener("datachannel", event => observeChannel(event.channel));
      peer.addEventListener("track", async event => {
        if (event.track.kind !== "audio") return;
        const context = new AudioContext();
        await context.resume();
        const analyser = context.createAnalyser();
        context.createMediaStreamSource(new MediaStream([event.track])).connect(analyser);
        const samples = new Float32Array(analyser.fftSize);
        function sample() {
          analyser.getFloatTimeDomainData(samples);
          const rms = Math.sqrt(samples.reduce((sum, value) => sum + value * value, 0) / samples.length);
          if (rms > 0.001) {
            probe.speechFrames += 1;
            probe.lastSpeechAt = performance.now();
            const current = probe.cases.at(-1);
            if (current) {
              current.firstAudioAt ??= performance.now();
              current.audioFrames += 1;
            }
          }
          if (peer.connectionState !== "closed") requestAnimationFrame(sample);
        }
        sample();
      });
      return peer;
    },
  });

  probe.begin = text => {
    const id = `structured-${probe.cases.length + 1}`;
    probe.cases.push({ id, text, output: [], audioFrames: 0, sentAt: performance.now(), speechFramesAtStart: probe.speechFrames });
    return id;
  };

  probe.evidence = async () => {
    let audioPackets = 0;
    for (const peer of probe.peers) {
      for (const report of (await peer.getStats()).values()) {
        if (report.type === "inbound-rtp" && report.kind === "audio") audioPackets += report.packetsReceived;
      }
    }
    return {
      audioPackets,
      speechFrames: probe.speechFrames,
      timeline: probe.events.filter(item => ["bot-output", "bot-started-speaking", "bot-stopped-speaking", "llm-function-call-in-progress", "llm-function-call-stopped"].includes(item.type)),
      cases: probe.cases.map(item => ({ text: item.text, output: item.output, error: item.error, audioFrames: item.audioFrames, completed: !!item.completedAt, sentAt: item.sentAt, completedAt: item.completedAt, outputAt: item.outputAt, firstAudioAt: item.firstAudioAt, firstAudioMs: item.firstAudioAt ? item.firstAudioAt - item.sentAt : null })),
      output: probe.events.filter(item => item.type === "bot-output" && item.data.spoken_status === "new").map(item => item.data.text),
      toolsStarted: probe.events.filter(item => item.type === "llm-function-call-in-progress").length,
      toolsCompleted: probe.events.filter(item => item.type === "llm-function-call-stopped").length,
    };
  };
  return "structured probe installed";
})();
