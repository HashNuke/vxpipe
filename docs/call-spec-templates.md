# Call spec templates

Call spec templates are portable scenario samples that can be rendered for and installed
into any tenant. Each template chooses its telephony service, models and providers from
inputs supplied at install time. The library is local under
[`samples/callspecs`](../samples/callspecs/README.md) for now. There is no Console UI.

## Format

One directory per template, named by the template ID:

- `manifest.json` holds the ID, name, description, `template_version`, the
  `call_spec_schema_version` the template produces, `inputs` and `examples`.
  `inputs` is a JSON Schema (draft 2020-12) object for the input map. Top-level
  `default` values are applied before rendering.
- `template.json.liquid` is a Liquid template whose output is call spec JSON.

The format is data only. It needs no Elixir code, so a template can be published
in a central library and rendered by any Liquid runtime.

## Rendering contract

`Vxpipe.Calls.CallSpecTemplate` loads and renders one template with
[Solid](https://hexdocs.pm/solid/). Its rules are:

- Every `{{ ... }}` output must end with the `json` filter, which JSON-encodes the
  value. Text inputs therefore cannot change the document structure. Longer strings
  are built with `capture` and then emitted through `json`. Templates that break
  this rule fail to load with `:unescaped_output`.
- Only the `assign`, `capture`, `case`, `comment`, `for`, `if` and `unless` tags (plus
  inline comments, `break` and `continue`) are allowed. `echo`, `raw`, `render`,
  counters and cycles are rejected at load.
- Every declared top-level input is bound, either to its value, its default or `nil`.
  Strict variables and filters turn a misspelled name into a render error instead of
  an empty value.
- Inputs are validated against the manifest schema before rendering. The output must
  be a JSON object with the manifest's schema version, and it must pass the production
  call spec parser. The parser also checks the provider and model catalog.

Tenant-specific checks, such as whether the named telephony service and credentials
exist, happen when the rendered source is saved.

## Elixir API

```elixir
{:ok, templates} = Vxpipe.Calls.list_call_spec_templates()
{:ok, source} = Vxpipe.Calls.render_call_spec_template("dental-after-hours", inputs)

{:ok, %{status: :created, call_spec_id: id, revision: 1, published: false}} =
  Vxpipe.Calls.install_call_spec_template(authority, tenant_key, "dental-after-hours", inputs)
```

Installation requires call spec write authority for the tenant, the same authority as
ordinary authoring, and stores the source through `CallSpecAuthoring.save/4`. The
rendered `name` identifies an installation within the tenant:

- No spec with that original name: the rendering is saved as revision 1 (`:created`).
- A spec whose latest source is identical: it is returned unchanged (`:unchanged`).
- A different source, or an ambiguous name: `{:error, :call_spec_template_conflict}`.
  Installations never overwrite. Choose a different `name` input for another
  variant, for example one per provider combination.

Before saving a new spec, the installer runs the same tenant-aware checks that `save`
runs, such as plan compilation, credentials and services. A rendering that fails them
returns `{:error, {:call_spec_template_invalid, errors}}` and stores nothing, so fixing
the inputs and installing again works without renaming. The result still includes the
stored revision's `validation_errors`, because an unchanged spec may have become invalid
after it was installed. A `call_spec_id` option is ignored, because installations find their spec by name.

Pass `publish: true` to also publish the installed revision. Publishing applies the
normal publication checks, such as phone number ownership and outbound caller ID.

The library directory defaults to the checkout's `samples/callspecs`. Set
`VXPIPE_CALL_SPEC_TEMPLATES_DIR` to use another directory at runtime, which releases
must do. Pass `directory:` in options to use another library for a single call.
`list/1` fails if any template in the library is invalid, so a broken template
is not silently left out.

## Decisions and rejected alternatives

- **Liquid over JSON** was chosen over `.exs` templates. Executable templates could
  not safely come from a shared library, and Liquid is sandboxed and portable.
- **Mandatory `json` filter** was chosen over string interpolation into JSON. Plain
  interpolation breaks or rewrites the document when a value contains quotes or newlines.
- **JSON Schema inputs** were chosen over a custom input format. JSV already validates
  call variable schemas here, other clients can validate inputs the same way, and a
  future UI can generate a form from the schema.
- **Name-keyed, non-overwriting installs** follow the existing demo sample installer.
  Re-running an install is safe, and edits made in a tenant are never replaced silently.

## Verification

`apps/vxpipe_calls/test/vxpipe/calls/call_spec_templates_test.exs` covers the
following:

- Every manifest example in the checked-in library renders and passes the production parser.
- Defaults are applied, and web connections are chosen when `telephony` is omitted.
- Phone connections are used when `telephony` is supplied.
- Text that contains JSON syntax stays a JSON string.
- Inputs that fail the schema are rejected.
- Parser errors in the rendered source are returned.
- Unknown IDs and path traversal are reported as not found.
- Templates with unescaped output or forbidden tags fail to load, and undefined
  variables fail to render.
- Install authorization, idempotent reinstalls, publication and conflicts are checked.
- A rendering that fails tenant validation stores nothing, a tenant's later revision
  (even an invalid one) is never replaced, and a supplied `call_spec_id` is ignored.
- Escape checks inside `for`, `if`, `unless`, `case` and `capture` blocks, and a filter
  after `json`, are tested.
