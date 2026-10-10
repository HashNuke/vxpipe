---
target: Call settings and variable modal design review
total_score: 29
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 0
target_identity: "file:apps/vxpipe_console/assets/src/admin/callSpecEditor/variables-panel.tsx"
target_fingerprint: "sha256:fcfb8aa3f7b41f8a8651931a37781783ab0ec00a1910916ef98d033fd490d1d6"
target_path: apps/vxpipe_console/assets/src/admin/callSpecEditor/variables-panel.tsx
timestamp: 2026-10-10T13-22-23Z
slug: admin-callspeceditor-variables-panel-tsx-57bc91c2
---
Method: dual-agent (A: design_review · B: design_evidence), assessed independently before synthesis.

The section-card inventory and shared add/edit modal fit Vxpipe’s operator workspace. Entry owns routing, call direction is a quiet header readout, and variable access remains with the agent that needs it. This is a refinement of the existing visual system.

| Heuristic | Score | Assessment |
| --- | ---: | --- |
| System status | 3/4 | Active tabs, variable type/required summaries and modal actions are clear. |
| Match with real world | 3/4 | Routing ownership is natural; schema terminology remains technical. |
| Control and freedom | 3/4 | Cancel, Escape and focus return work; deletion has no local recovery. |
| Consistency | 4/4 | Uses the existing controls, palette and layout rules. |
| Error prevention | 2/4 | Empty/duplicate variable names are guarded; section deletion is immediate. |
| Recognition over recall | 3/4 | Section context and agent-access guidance stay visible. |
| Efficiency | 3/4 | Compact overview; deeply nested schemas still require scrolling. |
| Minimalist design | 3/4 | Inventory is focused; nested labels needed shortening. |
| Error recovery | 3/4 | Name errors preserve the modal draft. |
| Help | 2/4 | Useful ownership guidance; schema terms could use more explanation. |
| **Total before refinement** | **29/40 — Good** | No blocking findings. |

The score records Assessment A before the bounded refinement, rather than an invented post-fix rescore.

What works:

- Each section’s rows expose name, type and required status without displaying every schema control.
- The modal retains section context and visible Save/Cancel actions while its body scrolls.
- The ownership changes match the task: Entry controls Handled by; agents control access; call settings controls shared definitions.

Cognitive load is low for the overview and scalar fields, moderate for nested schemas. The main emotional valley is deeply nested editing; the clearest finish is the modal’s explicit save action. The design remains a compact technical workbench rather than a decorative card dashboard.

The three-file CLI detector reported no findings. Browser evidence identified repeated nested labels with tight leading, skipped heading levels, and a 16px modal close target. Card nesting was intentional per the requested section grouping; the detector’s Inter-font and compact type hierarchy findings conflict with the established product design. React Flow attribution is outside this change. A marginal 4.49:1 contrast result lacked a stable identified element and was not treated as a verified target defect.

One refinement batch addressed the actionable presentation findings:

- Nested visible labels now use local names such as Type and Allowed values; full path-based accessible names remain intact. Label line-height is 1.375.
- Call settings is an h2 and Array items follows the dialog heading without a skipped level.
- This modal’s close target is 36×36px.
- Section-level validation Show requests now expand their disclosure even when Variables is already mounted. A focused failing test preceded that fix.

The final confirmation inspected dark desktop at 1440×1000 and light mobile at 390×844. The nested modal measured 358×812, stayed inside the viewport, and kept its footer visible with internal scrolling. Keyboard containment, Escape and return focus were verified by the independent passes. A browser add/required/save action produced a new row. No page-level horizontal overflow was observed. Exhaustive assistive-technology testing was not performed.

One remaining priority observation:

- **P2: inherited section deletion has no local undo or confirmation.** Removing a section also removes grants and clears dial-routing references. This predates the requested reorganization. A future undo or concise confirmation naming affected data would improve recovery; use Impeccable harden for that separate interaction change.

Persona observations: the power operator benefits from compact rows and shorter labels; the keyboard user retains complete accessible names and familiar dialog behavior; the mobile operator has stable actions while editing long schemas. Existing 36px edit/remove controls remain smaller than the skill’s preferred 44px touch target but match the current product system.

Questions skipped: one remaining non-blocking Priority Issue, below the three-issue threshold.
