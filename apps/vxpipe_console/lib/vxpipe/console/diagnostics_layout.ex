defmodule Vxpipe.Console.DiagnosticsLayout do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!doctype html>
    <html lang="en" phx-socket="/diagnostics/live">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={@csrf_token} />
        <link rel="icon" href="data:," />
        <title>Vxpipe diagnostics</title>
        <style>
          :root {
            color-scheme: light;
            --ink: oklch(0.141 0.005 285.823);
            --charcoal: oklch(0.21 0.006 285.885);
            --worktop: oklch(0.274 0.006 286.033);
            --muted: oklch(0.48 0.014 285.938);
            --divider-strong: oklch(0.705 0.015 286.067);
            --divider: oklch(0.92 0.004 286.32);
            --panel: oklch(0.967 0.001 286.375);
            --paper: oklch(0.985 0 0);
            --canvas: oklch(1 0 0);
            --green: oklch(0.51 0.13 162.48);
            --green-soft: oklch(0.95 0.055 162.48);
            --coral: oklch(0.6 0.185 22.23);
            --coral-soft: oklch(0.96 0.045 22.23);
            --violet: oklch(0.585 0.233 277.117);
            --blue: oklch(0.55 0.19 259.815);
            --focus: oklch(0.623 0.214 259.815 / 0.28);
            --sans: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            --mono: "Geist Mono", "SFMono-Regular", Consolas, "Liberation Mono", monospace;
          }

          * { box-sizing: border-box; }

          html {
            min-width: 320px;
            background: var(--panel);
            scrollbar-color: var(--divider-strong) var(--panel);
          }

          body {
            margin: 0;
            min-height: 100vh;
            background: var(--panel);
            color: var(--ink);
            font-family: var(--sans);
            font-size: 16px;
            line-height: 1.5;
          }

          ::selection {
            background: var(--charcoal);
            color: var(--paper);
          }

          a {
            color: inherit;
            text-underline-offset: 3px;
          }

          a:focus-visible {
            outline: 3px solid var(--focus);
            outline-offset: 3px;
          }

          button, input, select, textarea { font: inherit; }

          .diagnostics-shell {
            width: min(100%, 1600px);
            min-height: 100vh;
            margin: 0 auto;
            padding: 16px;
          }

          .topbar {
            display: flex;
            align-items: flex-start;
            justify-content: space-between;
            gap: 24px;
            padding: 4px 0 20px;
          }

          .brand-lockup h1 {
            margin: 0;
            font-size: 1rem;
            font-weight: 750;
            letter-spacing: -0.015em;
          }

          .brand-lockup h1 span { color: var(--muted); font-weight: 550; }

          .brand-lockup p {
            max-width: 64ch;
            margin: 4px 0 0;
            color: var(--muted);
            font-size: 0.875rem;
          }

          .topnav { display: flex; gap: 8px; }

          .nav-link {
            display: inline-flex;
            min-height: 36px;
            align-items: center;
            justify-content: center;
            border: 1px solid var(--divider-strong);
            border-radius: 6px;
            padding: 7px 14px;
            background: var(--canvas);
            color: var(--charcoal);
            font-size: 0.875rem;
            font-weight: 620;
            text-decoration: none;
            transition: background-color 150ms ease-out, border-color 150ms ease-out;
          }

          .nav-link:hover { background: var(--panel); border-color: var(--muted); }
          .nav-link--primary { border-color: var(--charcoal); background: var(--charcoal); color: var(--paper); }
          .nav-link--primary:hover { border-color: var(--worktop); background: var(--worktop); }

          .collection-strip {
            display: grid;
            grid-template-columns: minmax(250px, 1.4fr) repeat(3, minmax(120px, 0.65fr));
            overflow: hidden;
            border: 1px solid var(--divider-strong);
            border-radius: 4px 4px 0 0;
            background: var(--charcoal);
            color: var(--paper);
          }

          .collection-primary,
          .collection-readout {
            min-height: 76px;
            padding: 14px 16px;
          }

          .collection-primary {
            display: flex;
            align-items: center;
            gap: 12px;
          }

          .collection-readout { border-left: 1px solid var(--worktop); }

          .state-marker {
            width: 10px;
            height: 10px;
            flex: 0 0 auto;
            border: 2px solid var(--charcoal);
            border-radius: 50%;
            background: var(--green);
            box-shadow: 0 0 0 3px var(--green-soft);
          }

          .collection-strip[data-state="degraded"] .state-marker,
          .collection-strip[data-state="unavailable"] .state-marker {
            background: var(--coral);
            box-shadow: 0 0 0 3px var(--coral-soft);
          }

          .collection-strip[data-state="waiting"] .state-marker {
            background: var(--divider-strong);
            box-shadow: 0 0 0 3px var(--worktop);
          }

          .collection-primary h2 {
            margin: 0;
            font-size: 0.9375rem;
            font-weight: 700;
          }

          .collection-primary p {
            margin: 2px 0 0;
            color: oklch(0.82 0.01 286);
            font-size: 0.75rem;
          }

          .readout-label,
          .section-label,
          th {
            font-family: var(--mono);
            font-size: 0.6875rem;
            font-weight: 700;
            letter-spacing: 0.055em;
            text-transform: uppercase;
          }

          .readout-label { display: block; color: oklch(0.76 0.01 286); }

          .readout-value {
            display: block;
            margin-top: 4px;
            font-family: var(--mono);
            font-size: 0.875rem;
            font-variant-numeric: tabular-nums;
          }

          .workbench {
            display: grid;
            grid-template-columns: minmax(235px, 0.75fr) minmax(410px, 1.45fr) minmax(290px, 1fr);
            min-height: calc(100vh - 154px);
            border: 1px solid var(--divider-strong);
            border-top: 0;
            background: var(--canvas);
          }

          .workbench-column { min-width: 0; }
          .workbench-column + .workbench-column { border-left: 1px solid var(--divider); }

          .instrument-section { padding: 16px; }
          .instrument-section + .instrument-section { border-top: 1px solid var(--divider); }

          .section-heading {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: 12px;
            margin-bottom: 12px;
          }

          .section-heading h2,
          .section-heading h3 {
            margin: 0;
            font-size: 0.75rem;
            font-weight: 700;
            letter-spacing: 0.05em;
            text-transform: uppercase;
          }

          .section-heading--spaced { margin-top: 24px; }

          .section-note { color: var(--muted); font-size: 0.75rem; }

          .runtime-primary {
            padding: 20px 0 24px;
            border-bottom: 1px solid var(--divider);
          }

          .runtime-number {
            display: block;
            font-family: var(--mono);
            font-size: clamp(2.75rem, 5vw, 4.5rem);
            font-weight: 520;
            font-variant-numeric: tabular-nums;
            letter-spacing: -0.04em;
            line-height: 0.95;
          }

          .runtime-caption { display: block; margin-top: 8px; color: var(--muted); font-size: 0.8125rem; }

          .runtime-grid { margin: 0; }

          .runtime-grid div {
            display: grid;
            grid-template-columns: 1fr auto;
            gap: 16px;
            padding: 12px 0;
            border-bottom: 1px solid var(--divider);
          }

          .runtime-grid dt { color: var(--muted); font-size: 0.8125rem; }
          .runtime-grid dd { margin: 0; font-family: var(--mono); font-size: 0.8125rem; font-variant-numeric: tabular-nums; }

          .state-line {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-top: 16px;
            color: var(--green);
            font-size: 0.8125rem;
            font-weight: 650;
          }

          .state-line[data-state="stale"],
          .state-line[data-state="missing"] { color: var(--coral); }

          .state-line::before {
            width: 7px;
            height: 7px;
            border-radius: 50%;
            background: currentColor;
            content: "";
          }

          .fixture-status {
            margin: 0;
            color: var(--muted);
            font-size: 0.8125rem;
          }

          .fixture-status strong {
            color: var(--charcoal);
            font-family: var(--mono);
            font-weight: 700;
          }

          .fixture-actions {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 6px;
            margin-top: 12px;
          }

          .fixture-actions button {
            min-height: 34px;
            border: 1px solid var(--divider-strong);
            border-radius: 4px;
            padding: 6px 8px;
            background: var(--canvas);
            color: var(--charcoal);
            cursor: pointer;
            font-size: 0.75rem;
            font-weight: 650;
            text-align: left;
          }

          .fixture-actions button:hover { border-color: var(--muted); background: var(--panel); }
          .fixture-actions button:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
          .fixture-actions button[aria-pressed="true"] { border-color: var(--charcoal); background: var(--charcoal); color: var(--paper); }

          .fixture-detail {
            margin: 10px 0 0;
            color: var(--muted);
            font-size: 0.75rem;
          }

          .ledger {
            width: 100%;
            border-collapse: collapse;
            table-layout: fixed;
          }

          .ledger th {
            padding: 0 8px 8px;
            border-bottom: 1px solid var(--divider-strong);
            color: var(--muted);
            text-align: left;
          }

          .ledger th:first-child,
          .ledger td:first-child { padding-left: 0; }
          .ledger th:last-child,
          .ledger td:last-child { padding-right: 0; text-align: right; }

          .ledger td {
            overflow-wrap: anywhere;
            padding: 10px 8px;
            border-bottom: 1px solid var(--divider);
            font-size: 0.8125rem;
            vertical-align: top;
          }

          .ledger tbody tr:last-child td { border-bottom: 0; }
          .ledger tbody tr { transition: background-color 180ms ease-out; }
          .ledger tbody tr:hover { background: var(--panel); }

          .series-name { color: var(--charcoal); font-weight: 650; }
          .series-detail { display: block; margin-top: 2px; color: var(--muted); font-size: 0.75rem; }
          .measure { font-family: var(--mono); font-variant-numeric: tabular-nums; white-space: nowrap; }
          .outcome--ok { color: var(--green); }
          .outcome--fault { color: var(--coral); }

          .empty-state {
            min-height: 92px;
            display: flex;
            align-items: center;
            border: 1px dashed var(--divider-strong);
            padding: 16px;
            color: var(--muted);
            font-size: 0.8125rem;
          }

          .unavailable-panel {
            min-height: calc(100vh - 154px);
            border: 1px solid var(--divider-strong);
            border-top: 0;
            padding: clamp(28px, 7vw, 96px);
            background: var(--canvas);
          }

          .unavailable-panel h2 { margin: 0 0 8px; font-size: 1.375rem; letter-spacing: -0.02em; }
          .unavailable-panel p { max-width: 62ch; margin: 0; color: var(--muted); }

          .visually-hidden {
            position: absolute;
            width: 1px;
            height: 1px;
            overflow: hidden;
            clip: rect(0, 0, 0, 0);
            white-space: nowrap;
            clip-path: inset(50%);
          }

          @media (max-width: 1050px) {
            .workbench { grid-template-columns: minmax(220px, 0.8fr) minmax(440px, 1.6fr); }
            .workbench-column:last-child { grid-column: 1 / -1; border-top: 1px solid var(--divider); border-left: 0; }
            .workbench-column:last-child { display: grid; grid-template-columns: 1fr 1fr; }
            .workbench-column:last-child .instrument-section + .instrument-section { border-top: 0; border-left: 1px solid var(--divider); }
          }

          @media (max-width: 720px) {
            .diagnostics-shell { padding: 8px; }
            .topbar { display: block; padding: 4px 0 12px; }
            .brand-lockup p { margin-top: 2px; }
            .topnav { margin-top: 12px; }
            .nav-link { flex: 1; padding-inline: 10px; }
            .collection-strip { grid-template-columns: 1fr 1fr; }
            .collection-primary { grid-column: 1 / -1; border-bottom: 1px solid var(--worktop); }
            .collection-readout { min-height: 64px; border-left: 0; border-bottom: 1px solid var(--worktop); }
            .collection-readout:nth-of-type(3) { border-left: 1px solid var(--worktop); }
            .collection-readout:last-child { grid-column: 1 / -1; border-bottom: 0; }
            .workbench { display: block; min-height: 0; }
            .workbench-column + .workbench-column { border-top: 1px solid var(--divider); border-left: 0; }
            .workbench-column:last-child { display: block; }
            .workbench-column:last-child .instrument-section + .instrument-section { border-top: 1px solid var(--divider); border-left: 0; }
            .runtime-number { font-size: 3.25rem; }
            .instrument-section { padding: 14px 12px; }
            .ledger th, .ledger td { padding-right: 4px; padding-left: 4px; }
          }

          @media (prefers-reduced-motion: reduce) {
            *, *::before, *::after { scroll-behavior: auto !important; transition-duration: 0.01ms !important; }
          }
        </style>
        <script src={Vxpipe.Console.DiagnosticsAssetController.path()} defer></script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
