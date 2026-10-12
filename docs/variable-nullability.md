# Variable nullability

## Decision

Call Variables accept `null` by default at individual variable nodes, including
nested object properties and array item schemas. A section itself must remain an
object. This lets the compact variable editor omit a Nullable checkbox without
relying on each frontend to write a nullable type union.

The source schema subset accepts an optional boolean `nullable` keyword. Omitted
or `true` adds null acceptance; `false` suppresses this implicit widening. Explicit
JSON Schema type unions that already contain `"null"` remain valid and retain
their meaning. `nullable` is an authoring keyword, stripped before JSV compilation.
The original source schema is preserved in the call spec and resolved plan.

Compilation widens both `type` and `enum` for each nullable variable. For example,
`{"type":"integer","enum":[18,21]}` accepts `18`, `21`, or `null`, but rejects
`19` and `"18"`. Other bounds continue to apply to non-null values. A root enum is
still unsupported. No missing fields or sections are populated automatically.
Required metadata and the existing partial-update/completeness behavior are
unchanged.

## Alternatives and implications

Keeping the default only in the Console would leave API-created schemas behaving
differently, so the Engine owns the default. Rewriting persisted source to add
null type unions would introduce unnecessary source churn, so normalization is
limited to validator compilation.

This intentionally broadens null acceptance for existing schemas when compiled
by this runtime. JSON authors who need non-null fields can use
`{"type":"string","nullable":false}`. New schemas using the `nullable` keyword
require the updated backend; older runtimes reject that keyword. There is no
Nullable control in the Console. Existing explicit settings and constraints
survive editing unrelated fields.

## Verification

Focused Engine tests cover nullable scalar, enum, object, nested-property and
array-item values, explicit opt-out, invalid keyword values, strict section roots,
and continued rejection of incorrect non-null types/enum values. Compiler and
runtime variable tests pass. Console validation accepts boolean overrides and
rejects other values at the same path. Modal tests cover typed tags, duplicates,
large integer precision, hidden constraint preservation, and error navigation.
