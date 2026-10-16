# Call spec template library

Each directory is one portable call spec template. See
[call spec templates](../../docs/call-spec-templates.md) for the rendering contract
and the Elixir API.

| Template | Scenario |
| --- | --- |
| [dental-after-hours](dental-after-hours/README.md) | After-hours clinic line: appointment requests, billing handoff, emergency transfer to an on-call human |

## Adding a template

1. Create `<id>/` with a lowercase hyphenated ID.
2. Write `manifest.json`: `id`, `name`, `description`, `template_version`,
   `call_spec_schema_version`, a JSON Schema `inputs` object and at least one
   `examples` input map. Examples should use the credential-free `morse` and
   `fixture` providers where possible.
3. Write `template.json.liquid`. Emit every value as `{{ value | json }}`. Build
   longer text with `{% capture %}` and emit it through `json`.
4. Add a `README.md` that describes the scenario, the inputs and how to exercise it.
5. Run `mix test test/vxpipe/calls/call_spec_templates_test.exs` from
   `apps/vxpipe_calls`. Every example must render and pass the call spec parser.

When a template changes the call spec it produces, increment `template_version`.
