# Stabilize MCP dialog interactions

The authenticated static-peer browser pass reproduced a mobile dismissal when
switching from Authentication to Tools. Radix selects the tab on mousedown; the
shorter panel can recenter before release, so SetupDialog receives a backdrop click
and closes. Keyboard selection works. Independent source review also found that
production omitted the anchoring used by the prototype: management height depends
on CSS variables defined only on the anchored backdrop.

Preserve the existing visual system and explicit close controls. Add focused
failing regressions for gestures beginning inside and ending on the backdrop,
cancellation and busy transitions. Require a genuine backdrop gesture for outside
dismissal. Restore the production management layout's stable height and scrolling,
then verify complete pointer and keyboard interactions on desktop and mobile.
No speech or source-cutover state-machine change is involved; Lean is not applicable.

Five focused assertions failed against the original handler: inside-start release,
consumption, cancellation, busy-start and the actual MCP Tools gesture. The fix
passes all eleven original focused cases. Independent source review found no
blocker and suggested two additional boundary cases: release over content and a
different pointer's release. Both were added before final verification; all thirteen
focused cases pass. The broader frontend suite passes 1,062 tests, and TypeScript
and the actual isolated asset build pass. The two added tests have focused evidence
rather than a second full frontend run. All five root gates pass: format,
warnings-as-errors compilation, strict Credo, the umbrella suite (4,991 tests,
zero failures, 241 excluded, seed 721027), and unused-dependency validation.

In headless Chrome at 390×844, the saved Basic management dialog now stays at top 8,
height 580, bottom 588 across complete pointer clicks on Authentication and Tools.
Tools shows list_events. A press on a tab followed by release on the backdrop keeps
the dialog open. Computed layout places the footer at 522–587 and the scrollable tab
panel at 122–522. Long-form scrolling, genuine outside dismissal and desktop checks
continue in the same bounded inspection pass.

The genuine backdrop press/release dismisses once, and Escape still dismisses.
Expanded Own-client endpoint fields scroll within the Authentication panel on both
390×844 and 1280×900 viewports. Save changes is reachable at the bottom while the
Disconnect/Close footer stays visible. No edited credentials were submitted. At
1280×900 the dialog remains top 64, height 580 across tabs; pointer selection and
keyboard ArrowRight/Enter both display the tool list. The final mobile Tools capture
shows the complete stable frame and footer. These are headless Chrome mouse and
keyboard checks, not physical touch-device acceptance.

The user merged origin/main during this checkpoint (dc313719, containing 6847c925).
It changes only the API-key breadcrumb timing test and its labnote, with no overlap
requiring consolidation. Its 10-case ConsoleStories file passes after the merge.
The user requested pushnotify for any future pulled-change overlap that requires
resolution; no notification condition has occurred here.

Closing the unsaved Own-client edit preserves the same Basic connection and its
current generation. Basic disconnect then removes it from the connected inventory.
The browser session is saved privately and closed, and the owned Console/peer
process is stopped. Other checkout listeners are untouched.

Independent adversarial source/test/browser-evidence re-review found no
implementation blocker. Two evidence wording corrections narrow the documented
gesture guarantees to the observed event boundaries and describe the thirteen-test
selection as dialog/management tests. Both corrections are applied.
