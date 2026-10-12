import { LoaderCircle, Pause, Play, VolumeX } from "lucide-react";
import { Button } from "../components/ui/button";
import type { useWaitSoundPreview } from "./wait-sound-preview";

export function WaitSoundPreviewButton({ label, silent, disabled, active, preview, onClick }: {
  label: string; silent: boolean; disabled: boolean; active: boolean;
  preview: ReturnType<typeof useWaitSoundPreview>; onClick: () => void;
}) {
  const state = active ? preview.state : "idle";
  const playing = state === "playing";
  const loading = state === "loading";
  const remaining = Math.round((1 - preview.progress) * 100);
  const action = loading ? "Pause loading" : playing ? "Pause" : state === "paused" ? "Resume" : "Play";
  return <div className="relative size-9">
    <Button type="button" variant="ghost" size="icon" disabled={disabled} data-playback-state={state}
      className={`relative rounded-full transition-colors duration-150 motion-safe:active:scale-95 ${active ? "bg-primary/15 text-primary hover:bg-primary/25 hover:text-primary dark:hover:bg-primary/25" : "text-muted-foreground hover:text-foreground"}`}
      aria-label={silent ? `${label}: silence` : `${action} ${label} audio`} title={silent ? "Silence" : `${action} preview`} onClick={onClick}>
      {active && preview.hasDuration && <svg viewBox="0 0 36 36" className="pointer-events-none absolute inset-0 size-9 -rotate-90" aria-hidden="true">
        <circle cx="18" cy="18" r="16" fill="none" stroke="currentColor" strokeWidth="2" className="opacity-20" />
        <circle cx="18" cy="18" r="16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" pathLength="100" strokeDasharray="100" strokeDashoffset={preview.progress * 100}
          className={playing ? "transition-[stroke-dashoffset] duration-200 ease-linear motion-reduce:transition-none" : ""} />
      </svg>}
      {silent ? <VolumeX className="size-4" /> : loading ? <LoaderCircle className="size-4 animate-spin motion-reduce:animate-none" /> : playing ? <Pause className="size-3.5 fill-current" /> : <Play className="size-3.5" />}
    </Button>
    {active && preview.hasDuration && <span role="progressbar" aria-label={`${label} audio remaining`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={remaining} className="sr-only" />}
  </div>;
}
