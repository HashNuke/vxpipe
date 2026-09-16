type IconName =
  | "mic"
  | "speaker"
  | "send"
  | "arrow"
  | "check"
  | "code"
  | "close"
  | "message"
  | "log"
  | "event"
  | "reset"
  | "metrics";
const paths: Record<IconName, string> = {
  mic: "M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3ZM5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8",
  speaker: "M11 4 5 9H2v6h3l6 5V4ZM15 8a6 6 0 0 1 0 8M18 5a10 10 0 0 1 0 14",
  send: "m3 3 18 9-18 9 4-9-4-9ZM7 12h14",
  arrow: "M4 12h16m-6-6 6 6-6 6",
  check: "m5 12 4 4L19 6",
  code: "m8 5-6 7 6 7m8-14 6 7-6 7m-3-16-2 18",
  close: "m5 5 14 14M5 19 19 5",
  message: "M4 5h16v11H8l-4 4V5Z",
  log: "m8 9 3 3-3 3m5 0h3M4 4h16v16H4V4Z",
  event: "M12 3v3m0 12v3M3 12h3m12 0h3m-3.6-6.4-2.1 2.1M8.7 16.3l-2.1 2.1m10.8 0-2.1-2.1M8.7 7.7 6.6 5.6M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z",
  reset: "M4 8V4m0 0h4M4 4l4 4a7 7 0 1 1-2 7",
  metrics: "M4 19V9m5 10V5m5 14v-7m5 7V3",
};
export function Icon({ name }: { name: IconName }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={paths[name]} />
    </svg>
  );
}
