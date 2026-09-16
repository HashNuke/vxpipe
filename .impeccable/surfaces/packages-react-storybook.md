---
version: 1
slug: "packages-react-storybook"
primary_target: "packages/react/stories/Workbench.stories.tsx"
related_targets:
  - "packages/react/src/CallConsole.tsx"
  - "packages/react/src/styles.css"
  - "packages/react/stories/Workbench.tsx"
  - "packages/react/stories/GettingStarted.tsx"
  - "packages/core/src/index.ts"
---

# Storybook call workbench

Mode: Operate.

Audience: developers reviewing the proposed reusable call console and the host
application's setup flow. Task: open an example, inspect a call state, send sample
text, and follow the conversation, measurements, and protocol evidence.

## Direction and authority

This surface implements the existing **Operator's Bench** from [DESIGN.md](../../DESIGN.md)
and [PRODUCT.md](../../PRODUCT.md). The local direction contract lives in
[preview-body.html](../../packages/react/.storybook/preview-body.html). This is a
synthetic code prototype, with the existing fonts, sizes, shallow corners, neutral
panels, semantic colors, and flat bordered treatment retained.

THESIS: A conversation-first operator's bench, with RTVI events a single tab away.

OWN-WORLD: Inter prose and controls, Geist Mono readouts, quiet neutral surfaces,
and color assigned to state and participant identity.

STORY: Review setup, open an example, inspect or type into its call state, and
follow the resulting evidence.

FIRST VIEWPORT: Slim application navigation; right-aligned call actions; device
groups beneath; participants beside an unboxed transcript; composer below.
Conversation, Metrics, and Logs share the main working region.

FORM: A user-requested Storybook implementation of the established visual world.
This brief records its composition without changing global design direction.

## Built composition

- Dark is the default; light is an alternative with the same hierarchy. Theme
  switching is also available in the application bar.
- Storybook stories and native Controls own scenario, initial view, readiness,
  and fixture-timing selection. The call canvas has no prototype controls or
  banner, console title, tenant/protocol/revision metadata, or call-ID footer.
- The first call-header row places status, elapsed time, and Start/Leave call at
  the right. The second contains microphone and speaker icon toggles, each paired
  with a visibly bordered input/output device select. Accessible names and toggle
  state accompany the icons.
- Desktop uses a participant rail and an unboxed, speaker-attributed conversation.
  The composer remains beneath the active main view. At 600px and below the roster
  becomes a horizontal strip, device groups stack, and controls receive larger
  touch targets. At 800px and below event details stack beneath the list and the
  metric source column is omitted.
- Streaming messages show three sequentially bouncing dots before their
  timestamp. Reduced-motion preference leaves the dots static. Spoken text uses
  only a valid client-supplied character range; missing timing leaves plain text
  and an explicit unavailable state, without estimating alignment.
- Metrics display supplied values, units, and sources. Missing measurements read
  “Unavailable”; they are not rendered as zero. Logs contain RTVI events only,
  with filtering, feed pause/resume, direction, and selectable payload details.
- Ready state reads “No call active,” has an empty participant roster, and has
  unavailable metrics. Starting an example populates its synthetic call state.

## Examples, setup, and package boundary

Stories cover ready, conversation, ended, failed, agent handoff, human handoff,
microphone denied, unavailable word timing, Metrics, Logs, light theme, and
incomplete/complete setup. Getting Started has a four-step checklist and three
examples: voice conversation, agent handoff, and human handoff. Its sample service
form and example installation update in-memory state; opening an example reaches
the ready call view before Start call.

`@vxpipe/core` owns framework-neutral public client contracts: stable snapshots,
subscriptions, messages, participants, metrics, protocol records, and lifecycle,
text, and device commands. `@vxpipe/react` owns presentation and styles, consumes
only that public interface, and leaves client creation/disposal to its host.
The fake client, setup page, and application shell belong to `stories/` and are
excluded from package exports. Both packages remain private.

All examples are synthetic. No live media, microphone capture, audio playback,
WebRTC, provider requests, credential persistence, production adapter, or platform
bootstrap is implemented by this prototype. Fixture word timing demonstrates a
supplied range, and event payloads illustrate display rather than wire conformance.
Run and verification commands are in the [workspace README](../../packages/README.md).

## Finish evidence

The finish reviewer returned **ship** after all three reported findings were
fixed. No new visual assets or review suppressions were introduced. Reviewed
captures are local inspection evidence, not shipping raster assets:

- [Desktop conversation](../review/storybook/desktop.png)
- [Mobile conversation](../review/storybook/mobile.png)
- [Ready](../review/storybook/ready.png)
- [Metrics](../review/storybook/metrics.png)
- [RTVI Logs](../review/storybook/logs.png)
- [Light](../review/storybook/light.png)
- [Setup](../review/storybook/setup.png)
- [Mobile setup](../review/storybook/setup-mobile.png)

This brief documents the reviewed prototype. Live-call and durable-setup acceptance
remain governed by [the milestone index](../../docs/milestones/index.md).
