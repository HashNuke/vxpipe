import { useEffect, useRef, useState } from "react";

function release(audio: HTMLAudioElement) {
  audio.onended = null;
  audio.onerror = null;
  audio.pause();
  audio.removeAttribute("src");
  audio.load();
}

/** One preview at a time, owned by the panel rather than the call's playback. */
export function useWaitSoundPreview() {
  const current = useRef<HTMLAudioElement | null>(null);
  const [active, setActive] = useState<string | null>(null);
  const [error, setError] = useState<{ id: string; message: string } | null>(null);
  useEffect(() => () => {
    if (current.current) release(current.current);
    current.current = null;
  }, []);
  function stop() {
    const previous = current.current;
    current.current = null;
    if (previous) release(previous);
    setActive(null);
    setError(null);
  }
  function toggle(id: string, url: string) {
    const wasActive = active === id;
    stop();
    if (wasActive) return;
    const audio = new Audio(url);
    current.current = audio;
    setActive(id);
    const failed = () => {
      if (current.current !== audio) return;
      stop();
      setError({ id, message: "Couldn’t play this audio. Check the URL or try again." });
    };
    audio.onerror = failed;
    audio.onended = () => { if (current.current === audio) stop(); };
    void audio.play().catch(failed);
  }
  return { active, error, stop, toggle };
}
