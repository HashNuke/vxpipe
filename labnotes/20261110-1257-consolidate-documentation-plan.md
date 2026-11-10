# Consolidate documentation plan

The user requested an inventory and proposed topic list in `docs/_TOC.md`
before planning or performing consolidation. The intended audiences are users
installing/configuring/operating Vxpipe and developers maintaining its architecture
and implementation. The eventual handbook should be importable by `vxpipe-web`.

Enumerated all 120 existing files under `docs/`: 115 Markdown documents, four
JSON references and one Elixir experiment, totaling 1,832,589 bytes. Inspected
titles, section inventories and opening contract/status text across the Markdown
documents, with focused reads of the existing index, quickstart, ownership/tool
contracts and reference artifacts. This is a documentation inventory, not a
fresh implementation or provider interoperability audit.

Proposed one published index, eleven usage chapters and nine development
chapters. Every existing file has one main destination in the source inventory;
mixed usage/implementation documents may be split between the related guides.
Keep current shared contracts together, provider differences in adapter sections,
and useful dated evidence in labnotes. Do not preserve a duplicate legacy handbook.
No content moves, new page stubs, site edits or importer were implemented.

Findings that need reconciliation during the later rewrite:

- The current index covers only a small subset of the material. The architecture
  file alone is 296,773 bytes and includes accumulated implementation history.
- The editor guide describes UUID call-spec identity, whereas the dedicated
  identity document describes decimal database IDs. Do not merge those claims
  without checking the implemented contract.
- Earlier speech and MCP status/behavior statements conflict with later accepted
  decisions. Voice-catalog backend work is explicitly described as proposed.
- The repository README still calls Docker delivery a preview; the website's
  getting-started document is TODO. Installation, configuration and operations
  need coherent guides with verified scope rather than copied deployment claims.

Read the actual website's Astro/Starlight configuration, content schema and
existing English pages in the `../vxpipe-docs` checkout (remote
`HashNuke/vxpipe-web`). Its destination is `src/content/docs/en/docs/` and its
marketing homepage is a separate `src/content/docs/index.mdx`. The installed
Starlight loader excludes underscore-prefixed filenames and its page schema
requires `title`. None of the pre-existing Vxpipe Markdown docs has frontmatter.
The inventory also found many relative links into labnotes and application code;
these and downloadable JSON assets need deliberate treatment when content is
copied. Keep the import plan small and defer its exact implementation until the
topic proposal is reviewed.

Verification: an inventory comparison accounts for all 120 pre-existing paths
exactly once. The final checks validate source links, destination IDs, planned
page counts and whitespace. No automated test files or application changes are
needed for this proposal.
