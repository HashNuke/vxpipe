(async () => {
  if (window.vadProbe) throw new Error("Fixture microphone already installed");
  const context = new AudioContext({sampleRate: 8000});
  await context.resume();
  const source = await context.decodeAudioData(await (await fetch('/__vad/fixture.wav')).arrayBuffer());
  if (source.sampleRate !== 8000 || source.length !== 268985 || source.numberOfChannels !== 1)
    throw new Error('Human fixture format changed');
  const destination = context.createMediaStreamDestination();
  // Keep the microphone clock running between clips so RTP carries real silence.
  const silence = context.createConstantSource();
  silence.offset.value = 0;
  silence.connect(destination);
  silence.start();
  const track = destination.stream.getAudioTracks()[0];
  const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
  navigator.mediaDevices.getUserMedia = constraints => constraints.audio
    ? Promise.resolve(destination.stream) : original(constraints);
  const probe = {context, source, destination, track, events: [], peers: [], channels: [], plays: []};
  window.vadProbe = probe;
  probe.play = async ({pauseMs = 0} = {}) => {
    const crop = source.getChannelData(0).slice(0, 27200);
    const gap = Math.round(pauseMs * 8);
    const buffer = context.createBuffer(1, crop.length + gap, 8000);
    const samples = buffer.getChannelData(0);
    samples.set(crop.subarray(0, 12000));
    samples.set(crop.subarray(12000), 12000 + gap);
    const node = context.createBufferSource();
    node.buffer = buffer;
    node.connect(destination);
    const evidence = {sample_rate: source.sampleRate, source_frames: source.length,
      crop_frames: crop.length, pause_frames: gap, track_kind: track.kind,
      nonzero_samples: crop.reduce((count, value) => count + (value !== 0), 0),
      context_start: context.currentTime, browser_start_ms: performance.now(),
      browser_utc_ms: Date.now(), ended: false};
    probe.plays.push(evidence);
    const ended = new Promise(resolve => node.onended = () => {
      evidence.ended = true;
      evidence.browser_end_ms = performance.now();
      node.disconnect();
      resolve(evidence);
    });
    node.start();
    return ended;
  };
  const BasePeer = window.RTCPeerConnection;
  const observeChannel = channel => {
    probe.channels.push(channel);
    channel.addEventListener('message', event => {
      try { probe.events.push({at: performance.now(), ...JSON.parse(event.data)}); }
      catch { /* Binary/non-RTVI traffic is not diagnostic evidence. */ }
    });
  };
  window.RTCPeerConnection = new Proxy(BasePeer, {construct(Target, args) {
    const peer = Reflect.construct(Target, args);
    probe.peers.push(peer);
    const create = peer.createDataChannel.bind(peer);
    peer.createDataChannel = (...args) => { const channel = create(...args); observeChannel(channel); return channel; };
    peer.addEventListener('datachannel', event => observeChannel(event.channel));
    return peer;
  }});
  return {sample_rate: source.sampleRate, source_frames: source.length, track_kind: track.kind};
})()
