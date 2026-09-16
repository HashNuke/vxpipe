type IconName =
  | "mic"
  | "speaker"
  | "send"
  | "phone"
  | "arrow"
  | "check"
  | "code"
  | "close";
const paths: Record<IconName, string> = {
  mic: "M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3ZM5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8",
  speaker: "M11 4 5 9H2v6h3l6 5V4ZM15 8a6 6 0 0 1 0 8M18 5a10 10 0 0 1 0 14",
  send: "m3 3 18 9-18 9 4-9-4-9ZM7 12h14",
  phone: "M5 16v4H1v-5c5-7 17-7 22 0v5h-4v-4M5 16l3-2M19 16l-3-2",
  arrow: "M4 12h16m-6-6 6 6-6 6",
  check: "m5 12 4 4L19 6",
  code: "m8 5-6 7 6 7m8-14 6 7-6 7m-3-16-2 18",
  close: "m5 5 14 14M5 19 19 5",
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
