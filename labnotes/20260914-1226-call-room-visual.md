# Call room visual

## Current scope and decisions

- The user subsequently rejected interactive illustrations without a hosted demo. The deliverable is now static SVG artwork with a static responsive preview.
- The user found the spatial node diagram confusing and specified nested containers. The current artwork has exactly two participants: Caller contains Speech-to-Text and AudioInput; Agent contains LLM and Text-To-Speech. Room separately contains CallRecording and AudioMixer.
- Containment is the visual relationship. Remove transfer/conversation edges, the third participant, and the capability satellites. Preserve the static-only constraint.
- Replaced the initial HTML simulation and its browser-interaction checker with landscape/mobile SVGs and a preview document. The original prototype was uncommitted; its source remains in the conversation's patch history.
- This is artwork exploration outside the published homepage, with no application-runtime changes.

## Initial exploration (superseded)

- Build one interactive homepage-artwork concept for review, outside the published homepage.
- The user rejected timelines: use spatial containment for the room, participant-owned capability attachments, and a transfer relationship between participants.
- Use handwritten SVG and local browser interaction; no D3 dependency is necessary for this small fixed topology.
- The illustrated call permits recording and STT. The pending human destination receives a private briefing before acceptance; commit releases the source AI execution and connects the human. This is illustrative data, not a live call or a complete transfer-state simulator.
- Read the architecture's capability, transfer, and presence-driven media-policy contracts. Preserve all existing worktree changes.

## Initial exploration verification (historical)

- Added a focused browser check before implementing the visual. It checks ownership, private preparation, transfer commit, source capability removal, stable room/recording, replay, and overflow.
- Red confirmed: the focused browser check reports `The visual must show a call room and participant capabilities` against the initial empty fragment.
- The preview renderer's sandbox iframe is not respected by agent-browser's JavaScript evaluation frame selection. For checks, flatten the renderer's own `srcdoc` into the local preview document; the same styles and scripts remain in use.
- Green: the browser ownership/transfer/replay check passes at 736px, 360px, and 320px. The final 736px and 320px checks use the corrected artwork.
- Inspected rendered light and dark views, with prepared and accepted transfer states. Fixed a desktop overlap between private-briefing and prepared-participant labels; increased secondary-label contrast. Removed the Tools attachment to keep this first drawing specifically about STT/LLM/TTS capabilities.
- The recording remains on the room boundary; participant capability badges remain structurally nested under their owners. The released agent is an explanatory outline of the source, not a claim that its execution is still active.
- Motion changes only the conversation connection after user input and honors reduced-motion preferences. Narrow layouts reposition the participants rather than shrinking the desktop SVG.
- The automatic design hook reported no deterministic issues. No published homepage files or application-runtime files were changed.
- `npm test`: 2 tests passed. Browser JavaScript executes without undefined identifiers; `node --check artwork/verify-call-room.js` passes. Diff whitespace checks pass.
- Root `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix credo --strict` passed. `mix test` did not complete: the persistence application stopped with `failed to start child: Vxpipe.Persistence.Repo` / `already started`. The worktree contains concurrent runtime changes; this visual does not modify them. `mix deps.unlock --check-unused` subsequently passed independently.

## Earlier static revision verification (historical)

- Both SVGs pass `xmllint --noout`.
- A static-content check confirms both SVGs and the preview contain no scripts, interactive controls, event handlers, or animation elements.
- Inspected the rendered preview in headless Chrome at 1200px and 390px. Labels, capability ownership, room boundary, and transfer arrow remain readable in both arrangements; the browser reports no interactive elements.
- `git diff --check` passes. This revision only replaces artwork/preview markup; the earlier umbrella-suite limitation remains historical and was not represented as a passing suite.
- The local preview at port 4869 now serves the static artwork directory, replacing the earlier interactive renderer.

## Container revision

- Updated both SVG compositions, preview alternate text, and README to the user's exact model and terminology.
- Nested structural rectangles are intentional here: the user explicitly requested containers as the abstraction. This takes precedence over generic design guidance against nested cards.
- Static artwork changes add no runtime behavior. Verification is XML parsing, ownership/content checks, and a rendered browser inspection of the same local file the user opened.
- Both SVGs pass XML parsing and XPath ownership checks: exactly two participants and six capabilities, the precise Caller/Agent capability names, and a room-capabilities group directly inside Room.
- Static checks confirm no scripts, controls, animation, flow paths, or arrow markers.
- Opened `artwork/index.html` directly through the file URL, matching the user's review path. Headless Chrome inspection at 1200px and 390px confirms readable labels and complete nested containers; no interactive elements appear.
- `git diff --check` passes. No runtime or dependency changes were made, so the umbrella suite was not repeated for this static revision.

## Current files and review boundary

- `vxpipe-docs/artwork/call-room.svg` is the landscape artwork; `call-room-mobile.svg` rearranges the same model for narrow screens.
- `vxpipe-docs/artwork/index.html` previews the static assets using an HTML picture element; `README.md` documents the local preview command.
- No external APIs, remote assets, dependencies, interactive controls, or live call operations are used. The drawing depicts ownership through containment, not a call execution sequence or media routing.
