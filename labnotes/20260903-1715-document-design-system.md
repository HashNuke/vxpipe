# Document design system

## 2026-09-03 — scan

- Impeccable `document` is running in scan mode because `samples/` contains a
  rendered React/Vite interface and imports Pipecat Voice UI Kit 0.13.1.
- The user identified the new `RoomDemo` / “Room lifecycle slice” top bar as an
  out-of-style addition. It is excluded from design authority and will be
  documented only as an anti-reference until it is brought into the system.
- `samples/src/styles.css` supplies only the page shell and the outlier room bar.
  The coherent visual system comes from the imported Voice UI Kit stylesheet and
  its rendered ConsoleTemplate components.
- Headless Chrome inspection used an isolated `agent-browser` session at
  desktop (1280px) and mobile (390px). Chrome required the CLI's documented
  `--no-sandbox` workaround because this host disables usable unprivileged user
  namespaces.
- Rendered light mode uses white canvas and cards, near-black ink, cool-gray
  borders and muted surfaces, green for active/connect state, red for inactive
  media controls, violet for agent identity, and blue for client identity. Dark
  mode maps the same semantic roles onto near-black canvas, charcoal cards,
  lifted gray controls, and near-white text.
- The imported base is a 4px spacing unit, a 6px base radius, 4px panel radius,
  150ms standard transitions, sans body/control type, and a 12px uppercase mono
  label system with 0.05em tracking. Panels are flat at rest with one-pixel
  borders; shadows are available primarily for overlays and transient depth.
- At 640px the console changes from a resizable desktop workspace (media,
  conversation, information, and events regions) to one active full-height panel
  with a fixed four-item bottom tab bar. The 390px render had no horizontal
  overflow.
- Representative rendered controls were inspected for computed size, spacing,
  color, radius, type, and interaction transitions. The active Connect button is
  36px high, medium-weight 14px sans text, a 6px radius, and uses the semantic
  active green without resting shadow.
- No root `DESIGN.md` exists, so there is no overwrite or merge decision. The
  next gate is the required two-round qualitative language interview before
  `DESIGN.md` and `.impeccable/design.json` are written.

## 2026-09-03 — qualitative language, round one

- The user selected **The Operator's Bench** as the creative north star.
- The confirmed system voice is **technical, calm, dependable**.
- The user approved the descriptive semantic color names **Signal Green**,
  **Engine Ink**, **Console Paper**, **Agent Violet**, **Client Blue**, and
  **Fault Coral**.

## 2026-09-03 — qualitative language, round two

- The user confirmed a flat, structural elevation philosophy: tonal layers and
  one-pixel borders at rest, with shadows reserved for overlays.
- The confirmed component character is compact, instrument-like, and
  state-explicit.
- The user confirmed that the system should reject both consumer-chat softness
  and decorative marketing treatments, in addition to excluding the current
  unstyled Room lifecycle slice bar from design authority.

## 2026-09-03 — design record

- Added root `DESIGN.md` in the alpha DESIGN.md format with all eight canonical
  sections in the required order. Frontmatter contains only observed color,
  typography, radius, spacing, and component tokens.
- Added `.impeccable/design.json` schema version 2 with color metadata and tonal
  ramps, typography metadata, overlay shadows, the 640px workspace breakpoint,
  the 150ms interaction transition, and seven self-contained component
  specimens.
- The design record treats the imported Pipecat console as the coherent
  incumbent system. It explicitly marks the new Room lifecycle slice bar as an
  outlier rather than carbonizing its browser-default controls.

## 2026-09-03 — verification

- Ruby YAML/JSON checks confirmed valid frontmatter, the exact canonical section
  order, only supported top-level token groups and component properties, matching
  color and color-metadata keys, exact canonical color values, eight-step tonal
  ramps, sidecar schema version 2, and seven component specimens.
- `jq` independently confirmed sidecar schema version 2, seven specimens, and
  the 640px workspace breakpoint.
- Trailing-whitespace checks and `git diff --check` passed.
- No application code changed, so the umbrella compile and test suite were not
  run for this documentation-only checkpoint.
