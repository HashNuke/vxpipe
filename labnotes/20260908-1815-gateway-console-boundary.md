# Gateway and console boundary

## Scope and decision

The user approved a separate Phoenix application named `vxpipe_console`, with
modules under `Vxpipe.Console`, including the existing reusable `vxpipe_gateway`.
Keep gateway library consumers independent of our browser presentation and Phoenix.
This checkpoint updates documentation only; no application conversion, rename,
generation, dependency installation or sample relocation is authorized by it.

## Inspection and progress

- Started with a clean worktree. Existing gateway owns a Plug HTTP endpoint,
  supervised session/connection runtime and an optional standalone HTTP listener;
  its Mix dependencies do not include Phoenix.
- Found no existing `Vxpipe.Console` namespace or `vxpipe_console` app in the
  inspected application/configuration sources. The sample remains React/Vite.
- Added the focused gateway/console decision, including rejected alternatives,
  embedding options and unchanged Ecto/Calls ownership. Updated the architecture
  and original call-definition design at their application-boundary sections.
- Delegated the four affected milestone/index updates under the user's standing
  request to use an agent when feedback resolves design questions. The existing
  milestone count/order and unchecked runtime acceptance gates must be preserved.
- Kept the plan additive: a console dependency on gateway is the starting point;
  make only evidence-backed mounting/configuration changes if later needed.
  Existing Plug support does not prove arbitrary host or transport compatibility.
- Clarified the user's intended deployment: console owns one Phoenix endpoint
  and listener and mounts the gateway Plug directly, with the gateway's standalone
  listener disabled. Gateway runtime supervision remains required. A standalone
  listener is an alternative for other hosts, not a second port in our console.

## Verification

- Reviewed the documentation diff and checked 117 relative file links across the
  eight changed/new documents; all resolve.
- All 23 ordered milestone checklist entries are unchanged against the committed
  index and remain unchecked. All 40 milestone prerequisite links still point to
  earlier entries. Architecture/design JSON examples are unchanged.
- `git diff --check` passed. Worktree changes are confined to the architecture,
  focused decision, four milestone/index documents and two labnotes.
- No runtime, dependency or UI changes; no Mix suite or browser verification is
  claimed. Console creation and embedded transport/route tests remain future work.
