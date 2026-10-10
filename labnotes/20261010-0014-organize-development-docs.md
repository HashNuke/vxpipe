# Organize development docs

## Scope and decisions

The user approved starting with development documentation under
`docs/development/`, keeping unrelated topics in separate documents. This is an
organizational checkpoint: preserve each source document's technical prose,
headings, examples, acceptance evidence and status. Do not perform the larger
refinement/archival rewrite proposed in the organization review yet.

Ten documents moved independently. `development.md` becomes
`local-development.md` to describe its content without a repeated
`development/development.md` path. All nine specialist documents retain their
original basenames. No `setup.md` combination, routing/styling merge or new
`docs/README.md` was implemented. The remaining 59 documents stay outside this
folder; their refinement remains deferred.

## Actual path map

| Previous path | Current document |
| --- | --- |
| `docs/development.md` | [Local development](../docs/development/local-development.md) |
| `docs/worktree-isolation.md` | [Checkout isolation](../docs/development/worktree-isolation.md) |
| `docs/live-provider-tests.md` | [Live provider tests](../docs/development/live-provider-tests.md) |
| `docs/live-telephony-harness.md` | [Live telephony harness](../docs/development/live-telephony-harness.md) |
| `docs/native-webrtc-testing.md` | [Native WebRTC testing](../docs/development/native-webrtc-testing.md) |
| `docs/sts-comparative-call-load.md` | [STS comparative call load](../docs/development/sts-comparative-call-load.md) |
| `docs/formal-verification.md` | [Formal verification](../docs/development/formal-verification.md) |
| `docs/mcp-client-conformance.md` | [MCP client conformance](../docs/development/mcp-client-conformance.md) |
| `docs/console-react-routing.md` | [Console React routing](../docs/development/console-react-routing.md) |
| `docs/react-component-styling.md` | [React component styling](../docs/development/react-component-styling.md) |

## Link repair and preservation

Rebased the moved documents' relative Markdown destinations from their new
directory, keeping links between moved topics local and links to other docs one
level up. Repaired repository inbound links and explicit prose/comment paths in
developer guides, labnotes, milestones, package/asset READMEs, `AGENTS.md`, the
live-test runner help, its public environment template and a test comment.
Examples and runtime behavior remain unchanged. The milestone index needed one
link destination repair; its ordering, completion states and review evidence are
unchanged.

The worktree already contained substantial staged and unstaged work before this
checkpoint. Inspected its status and compared changes against a fresh working-tree
snapshot so prior edits are preserved. No staging or commits were performed.
The private provider environment file was neither read nor modified. Setup had
already passed in this checkout before delegation; it was not rerun for these
documentation moves.

## Verification

- Before/after snapshots prove all ten source bodies are identical after
  normalizing only Markdown link destinations. Headings and fenced command/code
  examples are individually identical. All original source paths are absent and
  all ten destination files exist.
- A repository Markdown link scan checked 1,942 local file/fragment references
  before and 1,953 after the moves and proposal amendment: 29 preexisting failures
  and **zero new failures**. All ten links in this new checkpoint labnote also
  resolve.
  The scan resolves inline and reference-style destinations and Markdown heading
  anchors, excluding fenced examples, external URLs and path templates. Existing
  unrelated link defects were preserved rather than folded into this checkpoint.
- Every milestone's Markdown checklist completion markers match the pre-change
  snapshot. The milestone index changed only its one inbound harness link.
- The parent agent independently compared all ten document bodies, headings,
  fenced examples and ordered outgoing link targets with its separate baseline;
  that review passed, including document counts and milestone-index preservation.
- `git diff --check` passed, as did separate `git diff --no-index --check`
  whitespace checks for the ten untracked moved documents and this new labnote.
  Final status and snapshot diffs were inspected. The inventory remains 69 docs,
  with ten under `docs/development/` and 59 outside it. Runtime
  suites and hosted-service calls are unnecessary for these moves and path-only
  prose/comment changes.

## Follow-up

The organization proposal now records the user's correction: keep these ten
development documents separate. Its tree, counts and development rows now use
the ten actual paths, with an amendment explaining the superseded merges.
The original proposal's verification section is labeled as historical. User-facing
documentation refinement and README navigation remain separate follow-up work.

## Subsequent routing-document correction — 2026-10-10

After the organizational move, the user asked to omit Storybook navigation and
unsaved-editor guards from development routing documentation. Removed the
Storybook navigation discussion, the Editor navigation section and the
unsaved-change blocker rationale from `docs/development/console-react-routing.md`.
The production Console/Playground routes and Phoenix/client routing boundary
remain. The initial body-preservation verification above describes the move
before this separately requested content correction. No runtime code or
unrelated editing guide changed. Verified the correction diff, absence of the
removed topics and whitespace; the routing document has no Markdown links.
