# Compact wait-sound rows

- Replaced the duplicate inline URL field with an explicit URL modal. Edits are
  temporary until Use audio; cancel/close preserves the existing selection.
- Followed the subsequent compact-row direction: aligned label, selector, and
  preview control. The URL edit pencil sits inside the field. Silence disables
  playback. This supersedes the earlier three-card layout idea.
- Built-in previews import the same PCM WAV assets used by the call engine.
  Added the esbuild WAV file loader; relative asset URLs resolve beside admin.js.
  Files are loaded on preview, not embedded into the bundle or duplicated.
- One player owns all previews, releases playback when changing selection or
  leaving the panel, and handles failed playback and stale promise rejections.
- Red: modal tests failed because choosing Audio URL immediately mutated source
  and rendered an inline input. Preview tests failed before the hook existed.
- Green: 19 focused tests, all 592 frontend tests, TypeScript and lint pass.
  Production esbuild emits both built-in WAV assets successfully.
- Browser inspection: desktop and 390px mobile rows/modal, invalid URL rejection,
  custom URL confirmation, edit/cancel, real built-in and custom playback.
  Widened the shared label column after observing one wrapped label.
- Full umbrella completion checks are running. No speech state changes; Lean
  does not apply.
