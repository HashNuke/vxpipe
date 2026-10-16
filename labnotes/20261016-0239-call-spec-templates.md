# Call spec templates

## Goal

Make portable, templated call spec samples that can be loaded into any tenant without a UI.
The telephony service, models and providers come from install-time inputs. Templates are
Liquid over JSON (Solid), kept locally in `samples/callspecs`. The first scenario is an
after-hours dental line.

## Decisions

- Templates are Liquid over JSON rather than `.exs`. The user wants a central, distributable
  library, and executable templates could not safely come from one.
- Every output must end with `| json`. This is enforced by walking the Solid parse tree:
  `Solid.Object` nodes outside `capture`/`assign` must have `json` as their last filter.
  The allowed tags exclude `echo`, `raw` and `render`, so objects are the only way to emit
  values and templates cannot read files.
- Manifest `inputs` is JSON Schema, validated with JSV, which `vxpipe_calls` now depends on
  directly. JSV does not apply defaults, so top-level `default`s are merged in code. Every
  declared top-level property is bound (`nil` if absent), so `{% if telephony %}` works
  under `strict_variables`.
- Install keys on the rendered `name`, the same as the `DemoSamples` original-name lookup.
  An identical source is reused, a different one is a conflict, and nothing is overwritten.
- The library directory is set in `config/config.exs` from `__DIR__`. This is fine for
  checkouts. Releases must override it.

## Findings

- `Solid.render/3` with strict options returns `{:error, errors, partial}`. Values passed to a
  custom filter arrive unchanged as maps, and there is no HTML escaping.
- `JSV.normalize_error/2` defaults to atom keys, so `keys: :strings` is passed.
- `mix run --no-start` cannot validate ReqLLM model selections (for example
  `google`/`gemini-2.5-flash`) because the provider registry is not started. Under
  `mix test` it works.
- The test memory repository lacked `find_by_original_name`, so it was added there to match
  the Postgres store's semantics: revision 1's name, ordered by ID, limit 2.

## Evidence

- Red: 14 tests, 14 failures (modules undefined).
- Green: `apps/vxpipe_calls` `mix test test/vxpipe/calls/call_spec_templates_test.exs`
  passed with 14 tests and 0 failures.

## Review round 1

The review subagent checked the `| json` enforcement and found no bypass. Template
semantics were sound for cascade and speech-to-speech, over both web and phone.
Its findings, and what was done:

- **Invalid draft claimed its name.** Rendering does not run the tenant-aware compiler
  (`CallSpecs.save` stores those failures as `validation_errors`). A speech-to-speech
  install without an output transcript was saved as `:created`, and corrected inputs then
  hit a conflict. Fixed:
  - The result now includes `validation_errors`.
  - A never-published spec whose latest revision had errors got the new rendering as a
    revision (`:revised`). This was replaced in round 2.
  - An `output_speech_to_text` input was added.
- **`call_spec_id` passed through.** Options went through to `CallSpecAuthoring.save`,
  which appended to an unrelated spec. Fixed by dropping it.
- **Hard-coded library path.** The path in `config.exs` is now overridable with
  `VXPIPE_CALL_SPEC_TEMPLATES_DIR` in `runtime.exs`.
- **Manifest input checks.** Patterns were added for E.164 numbers and the service
  name (not `web`).
- **Test gaps.** Tests were added for escaping inside blocks, a filter after `json`,
  speech-to-speech over telephony, and the installer fixes.
- **Formatting.** The reported `mix format` failure did not reproduce: the root
  `mix format --check-formatted` passed.
- These new tests were written before the fixes, but they were only run after the
  fixes, so the red step was not observed for them. They then passed: 19 tests, 0 failures.

## Review round 2

- The reviewer reproduced a problem with `:revised`. `published?/2` really meant "the
  latest revision is not the published one", so a reinstall could append over a
  tenant's own invalid edit and publish the result, replacing the live published revision.
- Decision: remove `:revised` entirely. Add `CallSpecs.validate/3` and
  `CallSpecAuthoring.validate/4`, which run the save-time checks without storing:
  `CallSpec.new`, credentials and services, and plan compilation. The installer validates
  before creating a spec, and an invalid rendering returns
  `{:error, {:call_spec_template_invalid, errors}}` and stores nothing.
  - An existing spec is now only ever reused unchanged or reported as a conflict.
  - This also closes the race the reviewer noted, where a tenant save landing between the
    installer's read and its revise save was silently superseded.
- Rejected: limiting revise to `revision == 1` or adding an installer marker. Both still
  overwrite and add state. Validating first avoids storing bad drafts at all.
- Still open (reviewer, low): an `:unchanged` spec whose stored `validation_errors` came
  from a temporary failure can't be re-validated by reinstalling. The result reports the
  errors. Use a new name, or save a revision through the normal API.
- Hygiene: `apps/vxpipe_calls` has no `.formatter.exs`, so root
  `mix format --check-formatted` doesn't check it. That gap predates this work. Running
  `mix format` on the whole app reformatted 7 unrelated files; those were restored and
  only the touched files were formatted.
- Red for the round-2 tests was observed: 20 tests, 2 failures, for the expected reasons.
  Green: 36 tests, 0 failures across the template, call_specs and authoring test files.

## Always-create installs

- The user decided sample installs should not be idempotent. Every install creates a new
  call spec, even with identical inputs.
- Removed: the name lookup, the `:global` lock, the `:unchanged` status and
  `:call_spec_template_conflict`. Removing them also removes the reviewer's leftover
  low-severity issue about stale `validation_errors` on `:unchanged` specs.
- The result is now `%{template_id, call_spec_id, revision, published}`. Validation still
  runs before saving, and `call_spec_id` is still dropped from options.
- The test memory repository's `find_by_original_name` was removed because nothing uses it.
- Red was observed: the new always-create test failed because the second install reused
  the first spec. Green: 18 tests, 0 failures.
