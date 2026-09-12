# Sample voice-console accessibility

Status: open review issue. This does not block the context-compaction runtime
milestone, but it should be resolved before treating the sample voice console
as an accessible reference client.

## Observed behavior

The rendered voice console remains usable and has no horizontal overflow at
desktop or 390 x 844 mobile widths. An automated WCAG audit of the connected
mobile conversation view nevertheless reports:

- icon-only and tab controls supplied by the Voice UI Kit without accessible
  names;
- insufficient contrast for the destructive disconnect control and client
  speaker label; and
- no level-one heading in the playground page shell.

The corresponding desktop audit also reports an unfocusable scrollable region.
These findings were present while exercising the unmodified third-party console
components; the missing page heading belongs to the Vxpipe sample shell.

## Follow-up boundary

Review the current Voice UI Kit release and its supported component props before
adding local wrappers. Prefer an upstream upgrade or supported accessible labels
over patching package internals. Add a meaningful page heading in the Vxpipe
shell, visually hidden if the compact console layout should remain unchanged.
Only add local contrast overrides after confirming they remain compatible with
both light and dark themes.

## Verification

- Re-run the rendered console at desktop and 390 x 844 mobile widths.
- Exercise disconnected, connected, conversation, tool-call, and disabled-send
  states in both themes.
- Run the browser accessibility audit and require zero critical or serious
  violations attributable to the sample shell or its selected component API.
- Confirm keyboard focus reaches every tab, selector, scrollable transcript,
  and message control in a logical order.
