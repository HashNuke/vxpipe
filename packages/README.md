# Vxpipe browser packages

Private npm workspaces for the future `@vxpipe` packages. From the repository root:

```sh
npm ci
npm ci --prefix apps/vxpipe_console/assets
npm run build
npm run storybook
```

Open [Storybook](http://127.0.0.1:6006). Node 22.12+ is required. The server binds to
loopback, and serves the prototype independently of Phoenix, PostgreSQL and provider credentials.

## Packages

| Package | Responsibility |
| --- | --- |
| [@vxpipe/core](core) | Framework-neutral TypeScript call-details store, revision reconciliation, host loading controller, and live-control contracts. |
| [@vxpipe/react](react) | TypeScript React components consuming the injected Core controller; package-owned CSS and prototype stories. |

Both packages are `private: true`. Nothing is published or reserved on npm. The Phoenix asset
project and documentation site retain their own dependency installations. The repository-root
Storybook is the single shared catalog for the Console-owned Admin stories, the `@vxpipe/react`
debug console, and the Getting Started prototype. Stories stay next to the package or application
that owns their UI; the root config discovers them together.
The root lockfile belongs to these workspaces; `npm run build` builds Core before React.

## Prototype scope

Use Storybook's **Controls** and stories to choose call state, view, theme and fixture word-timing
animation. Dark is the default; light is available for review. The canvas contains the proposed
user interface, without preview controls, prototype notices, protocol/transport badges or tenant
labels on the call page. Preview explanations belong here and in story metadata.

All data is synthetic and in memory. The microphone/speaker controls simulate UI state: no
microphone capture, audio playback, WebRTC connection, provider request or credential storage
occurs. The word highlight demonstrates a supplied timing range; it is not real TTS alignment.
The example event payloads illustrate presentation, not an executable wire-protocol fixture.

Stories cover a conversation, ready/ended/failed calls, agent/human handoff, denied microphone,
missing timing, metrics, RTVI-only events, and partial/complete setup. You can send text, leave,
change devices, filter/pause/inspect events, switch themes, and complete the sample setup form.
Use sample values in that form. Reloading discards prototype setup state.

The `packages/react/stories/` directory owns the fake controller and the application-specific Getting Started page;
neither is exported by the React package. Real protocol/media adapters, platform bootstrap,
durable setup and production route integration remain in the [milestones](../docs/milestones/index.md).

## Verification

```sh
npm test
npm run check
npm run build-storybook
```

The package builds emit ESM and declarations to ignored `dist/` directories. The shared Storybook builds
to ignored `storybook-static/` at the repository root. The story preview bundles local fonts for offline
review. Vite polling is enabled for this preview because native file watching served stale source
on the development machine; generated output directories are excluded.
