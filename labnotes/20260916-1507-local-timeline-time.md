# Local timeline time

## Goal

Replace elapsed-looking conversation labels with readable viewer-local timestamps while preserving an unambiguous UTC instant.

## Decisions

- Timeline contracts use `occurredAt` as a UTC RFC 3339 instant. Call duration remains a separate elapsed value.
- Visible times use the browser locale and time zone with hour and minute.
- A Floating UI tooltip available on hover and keyboard focus shows the full local date/time, resolved IANA zone, and canonical UTC ISO timestamp.
- Timeline sorting uses the RFC 3339 instants and stable item IDs.

## Evidence

- Red: the focused test found no semantic `time[datetime]` for the call-connected event.
- Green: all 24 frontend tests and `npm run check` pass.
- Browser: inspected the human-handoff story at 1280×900 in `Asia/Saigon`. Timeline labels render as local `5:30 AM`/`5:32 AM`; the tooltip shows the full Indochina local time and `2026-09-16T22:30:00.000Z`.
