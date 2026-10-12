import { useEffect, useRef, useState } from "react";

type PlaybackState = "idle" | "loading" | "playing" | "paused";
function release(audio: HTMLAudioElement) {
  audio.onended = null;
  audio.onerror = null;
  audio.ontimeupdate = null;
  audio.ondurationchange = null;
  audio.onwaiting = null;
  audio.onplaying = null;
  audio.pause();
  audio.removeAttribute("src");
  audio.load();
}

/** One preview at a time, owned by the panel rather than the call's playback. */
export function useWaitSoundPreview() {
  const current = useRef<{ audio: HTMLAudioElement; id: string; url: string; paused: boolean } | null>(null);
  const attempt = useRef(0);
  const [active, setActive] = useState<string | null>(null);
  const [state, setState] = useState<PlaybackState>("idle");
  const [progress, setProgress] = useState(0);
  const [hasDuration, setHasDuration] = useState(false);
  const [error, setError] = useState<{ id: string; message: string } | null>(null);
  useEffect(() => () => {
    if (current.current) release(current.current.audio);
    current.current = null;
    attempt.current++;
  }, []);
  function stop() {
    const previous = current.current;
    current.current = null;
    attempt.current++;
    if (previous) release(previous.audio);
    setActive(null);
    setState("idle");
    setProgress(0);
    setHasDuration(false);
    setError(null);
  }
  function play(audio: HTMLAudioElement, id: string) {
    const request = ++attempt.current;
    setState("loading");
    void audio.play().then(() => {
      if (current.current?.audio === audio && attempt.current === request) setState("playing");
    }).catch(() => {
      if (current.current?.audio !== audio || attempt.current !== request) return;
      stop();
      setError({ id, message: "Couldn’t play this audio. Check the URL or try again." });
    });
  }
  function toggle(id: string, url: string) {
    const previous = current.current;
    if (previous?.id === id && previous.url === url) {
      if (previous.paused) {
        previous.paused = false;
        play(previous.audio, id);
      } else {
        previous.paused = true;
        attempt.current++;
        previous.audio.pause();
        setState("paused");
      }
      return;
    }
    stop();
    const audio = new Audio(url);
    current.current = { audio, id, url, paused: false };
    setActive(id);
    const updateProgress = () => {
      if (current.current?.audio !== audio) return;
      const known = Number.isFinite(audio.duration) && audio.duration > 0;
      setHasDuration(known);
      setProgress(known ? Math.min(1, Math.max(0, audio.currentTime / audio.duration)) : 0);
    };
    audio.ontimeupdate = updateProgress;
    audio.ondurationchange = updateProgress;
    audio.onwaiting = () => { if (current.current?.audio === audio && !current.current.paused) setState("loading"); };
    audio.onplaying = () => { if (current.current?.audio === audio && !current.current.paused) setState("playing"); };
    audio.onerror = () => {
      if (current.current?.audio !== audio) return;
      stop();
      setError({ id, message: "Couldn’t play this audio. Check the URL or try again." });
    };
    audio.onended = () => { if (current.current?.audio === audio) stop(); };
    play(audio, id);
  }
  return { active, state, progress, hasDuration, error, stop, toggle };
}
