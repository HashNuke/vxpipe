---
version: alpha
name: Vxpipe Operator's Bench
description: A compact operational console for voice-agent orchestration.
colors:
  engine-ink: "oklch(0.141 0.005 285.823)"
  bench-charcoal: "oklch(0.21 0.006 285.885)"
  worktop-gray: "oklch(0.274 0.006 286.033)"
  muted-readout: "oklch(0.552 0.016 285.938)"
  subtle-divider: "oklch(0.705 0.015 286.067)"
  divider-gray: "oklch(0.92 0.004 286.32)"
  panel-gray: "oklch(0.967 0.001 286.375)"
  console-paper: "oklch(0.985 0 0)"
  clean-canvas: "oklch(1 0 0)"
  signal-green: "oklch(0.696 0.17 162.48)"
  fault-coral: "oklch(0.7022 0.1892 22.23)"
  agent-violet: "oklch(0.585 0.233 277.117)"
  client-blue: "oklch(0.623 0.214 259.815)"
typography:
  title:
    fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.5
  body:
    fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  control:
    fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.4286
  bench-label:
    fontFamily: "Geist Mono, SF Mono, Consolas, Roboto Mono, monospace"
    fontSize: "12px"
    fontWeight: 700
    lineHeight: 1.3333
    letterSpacing: "0.05em"
  telemetry:
    fontFamily: "Geist Mono, SF Mono, Consolas, Roboto Mono, monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  none: "0px"
  sm: "4px"
  md: "6px"
  lg: "8px"
spacing:
  micro: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-active:
    backgroundColor: "{colors.signal-green}"
    textColor: "oklch(0.9793 0.0207 166.11)"
    typography: "{typography.control}"
    rounded: "{rounded.md}"
    padding: "8px 18px"
    height: "36px"
  button-primary-light:
    backgroundColor: "{colors.bench-charcoal}"
    textColor: "{colors.console-paper}"
    typography: "{typography.control}"
    rounded: "{rounded.md}"
    height: "36px"
  button-primary-dark:
    backgroundColor: "{colors.divider-gray}"
    textColor: "{colors.bench-charcoal}"
    typography: "{typography.control}"
    rounded: "{rounded.md}"
    height: "36px"
  panel-light:
    backgroundColor: "{colors.clean-canvas}"
    textColor: "{colors.muted-readout}"
    rounded: "{rounded.sm}"
  panel-dark:
    backgroundColor: "{colors.bench-charcoal}"
    textColor: "{colors.console-paper}"
    rounded: "{rounded.sm}"
  segmented-tab:
    typography: "{typography.bench-label}"
    rounded: "{rounded.sm}"
    padding: "4px 8px"
    height: "33px"
  input:
    typography: "{typography.control}"
    rounded: "{rounded.md}"
    padding: "8px 12px"
    height: "36px"
---

# Design System: Vxpipe Operator's Bench

## Overview

**Creative North Star: "The Operator's Bench"**

The Operator's Bench treats each screen as a working instrument: technical,
calm, and dependable. The interface is compact and information-dense without
feeling hurried; hierarchy comes from alignment, mono labels, borders, and
restrained semantic color rather than decorative emphasis.

Surfaces stay quiet so state is unmistakable. Neutral panels form a stable
frame; Signal Green marks readiness and action, Fault Coral marks unavailable or
error states, and identity hues remain tied to agent and client roles. Controls
feel instrument-like and state-explicit.

**Key Characteristics:**

- Compact operational density
- Dual light and dark neutral work surfaces
- Sans-serif actions paired with uppercase mono labels and readouts
- Saturated color reserved for state and identity
- Flat, bordered panels with shallow corners

## Colors

The palette is a neutral instrument housing with bright, narrowly assigned
signals. Light and dark themes remap the same semantic hierarchy rather than
introducing separate personalities.

### Primary

- **Engine Ink** (`oklch(0.141 0.005 285.823)`): The darkest canvas and the
  strongest light-theme text.
- **Console Paper** (`oklch(0.985 0 0)`): Primary dark-theme text and the soft
  white used against dense controls.

### Secondary

- **Signal Green** (`oklch(0.696 0.17 162.48)`): Connection, readiness, and the
  principal affirmative action.
- **Fault Coral** (`oklch(0.7022 0.1892 22.23)`): Unavailable, disconnected,
  destructive, or failed operational state.

### Tertiary

- **Agent Violet** (`oklch(0.585 0.233 277.117)`): Agent identity and
  agent-originated information.
- **Client Blue** (`oklch(0.623 0.214 259.815)`): Client identity and
  client-originated information.

### Neutral

- **Clean Canvas** (`oklch(1 0 0)`): Light-theme page and panel surfaces.
- **Panel Gray** (`oklch(0.967 0.001 286.375)`): Light-theme grouped controls
  and muted regions.
- **Divider Gray** (`oklch(0.92 0.004 286.32)`): Light-theme panel borders and
  input strokes.
- **Subtle Divider** (`oklch(0.705 0.015 286.067)`): Secondary icons and quiet
  structural cues.
- **Muted Readout** (`oklch(0.552 0.016 285.938)`): Secondary copy and dormant
  values.
- **Bench Charcoal** (`oklch(0.21 0.006 285.885)`): Dark-theme panel surface.
- **Worktop Gray** (`oklch(0.274 0.006 286.033)`): Dark-theme grouped controls
  and raised tonal regions.

### Named Rules

**The State Owns Color Rule.** Saturated hues are reserved for operational state
and participant identity; neutral structure carries everything else.

**The Theme Is a Remap Rule.** Light and dark modes preserve hierarchy and
semantic assignments rather than merely inverting pixels.

**The Quiet Canvas Rule.** Do not add decorative gradients or brand color washes
to operational surfaces.

## Typography

**Title and Body Font:** Inter with the system sans-serif stack

**Label/Mono Font:** Geist Mono with SF Mono, Consolas, Roboto Mono, and
monospace fallbacks

**Character:** The sans-serif face keeps instructions and controls calm and
immediate. Monospaced labels and telemetry give the workbench its technical
cadence without turning all content into terminal cosplay.

### Hierarchy

- **Title** (700, 16px, 1.5): Compact workspace and product titles.
- **Body** (400, 16px, 1.5): Empty states, instructions, and general interface
  copy.
- **Control** (500, 14px, 1.4286): Buttons, selectors, and compact actions.
- **Bench Label** (700, 12px, 1.3333, 0.05em): Uppercase panel headings, tabs,
  and short operational categories.
- **Telemetry** (400, 12px, 1.5): Timestamps, identifiers, transport values, and
  event-stream data.

### Named Rules

**The Readout Split Rule.** Use sans-serif type for prose and actions; use mono
for terse labels, identifiers, status values, and timestamps.

## Layout

The console uses a 4px base unit with working intervals at 8px, 12px, 16px,
24px, and 32px. Desktop gutters are intentionally tight: panels commonly sit
inside 8px padding with 8px to 16px gaps. Space communicates grouping, not
luxury.

At 640px and above, the interface becomes a resizable workspace: media,
conversation, and information panels divide the main row, while the event stream
occupies a vertically resizable region below. Below 640px, one full-height panel
is active at a time and a fixed 48px bottom tab bar switches among media,
conversation, information, and events. The mobile header compresses to the logo
and essential controls, and horizontal scrolling is not permitted.

**The One Working Surface Rule.** Group related tools inside one bordered panel;
do not create decorative cards inside cards.

## Elevation & Depth

Depth is flat and structural. Core panels and controls use tonal layering and
one-pixel borders at rest, with no shadow. Short ambient shadows are reserved for
temporary overlays such as menus, popovers, and tooltips; opening an overlay is
the reason elevation appears.

**The Flat at Rest Rule.** Core work surfaces never float; one-pixel dividers and
tonal contrast define hierarchy. Shadows belong only to temporary overlays.

## Shapes

The form language is shallow and engineered. Panels and segmented controls use
gently clipped 4px corners; standard buttons and inputs use 6px corners; larger
8px corners are exceptional. Square and rectangular silhouettes dominate, with
full circles reserved for inherently circular controls or indicators.

**The Tool, Not Toy Rule.** Keep corners shallow and functional; do not turn
ordinary content, labels, or panels into pills.

## Components

Components are compact, instrument-like, and state-explicit. Each state change
must be legible through more than decoration alone.

### Buttons

- **Shape:** Shallow rounded rectangle (6px) at a standard 36px height.
- **Active / Connect:** Signal Green with pale signal text, 14px medium-weight
  sans type, and 8px by 18px padding.
- **Primary:** Engine Ink on light surfaces and Divider Gray on dark surfaces.
- **Ghost:** Transparent at rest, then a quiet neutral tonal fill on hover.
- **Focus:** A visible 3px semantic ring; hover and state transitions use the
  standard 150ms easing.

### Panels / Containers

- **Corner Style:** Shallow 4px corners.
- **Background:** Clean Canvas in light mode and Bench Charcoal in dark mode.
- **Shadow Strategy:** None at rest.
- **Border:** One-pixel neutral divider, including between panel headers and
  content.
- **Internal Padding:** Usually 8px, increasing to 12px or 16px when the panel
  width permits.

### Inputs / Fields

- **Style:** 36px high, 6px corners, neutral stroke or tonal fill, and compact
  14px text.
- **Focus:** A visible 3px neutral ring and border shift.
- **Error / Disabled:** Fault Coral owns errors; disabled controls reduce
  emphasis but keep their label and state readable.

### Navigation

- **Desktop:** Uppercase 12px mono tabs sit in a muted segmented track; the
  active tab returns to the base surface.
- **Mobile:** A 48px bottom bar exposes the four primary work areas as equal
  targets. Icons require accessible names even when visible labels are omitted.

### Status Readouts

Section headings use Bench Label typography. Human-readable row labels remain
sans-serif, while values and identifiers use telemetry mono. Use Signal Green,
Fault Coral, Agent Violet, and Client Blue only for their assigned semantics.

**The One State, One Signal Rule.** A control's color, label, icon, and disabled
treatment must agree about its operational state.

## Do's and Don'ts

### Do:

- **Do** build hierarchy from panels, alignment, tonal layers, and dividers.
- **Do** keep status colors tied to readiness, failure, agent, and client roles.
- **Do** use uppercase mono labels for terse categories and sans-serif type for
  readable instructions and actions.
- **Do** preserve the 640px transition from resizable workspace to single-panel
  mobile navigation.
- **Do** bring new custom surfaces onto these tokens before treating them as
  design authority.

### Don't:

- **Don't** use unstyled browser-default controls or the former Room lifecycle
  slice bar as design-system evidence.
- **Don't** soften the console into consumer chat styling with plush message
  bubbles, oversized pills, or friendly gradient cards.
- **Don't** import decorative marketing treatments such as hero-scale type,
  ornamental glows, or gradient backdrops into operational screens.
- **Don't** nest decorative cards inside working panels.
- **Don't** use saturated color as ornament; every bright hue must communicate a
  defined state or identity.
