# Saved credential placeholders

- User requested masked placeholders only for fields that have saved input. Added
  field-presence metadata to the credential form; no stored values are passed to it.
- Existing connections mark the required credential fields as saved. Telnyx public key
  is masked only when telephonyPublicKeyConfigured is true. New connections and new
  tenant overrides do not imply saved values from another scope.
- Placeholders use eight bullets and leave the actual input values empty. Submission
  validation remains unchanged; the bullets cannot be submitted as replacement secrets.
- Red: four focused modal cases yielded two expected failures for missing saved masks.
  Green: all 40 focused modal, onboarding, scoped-service and credential-form tests pass.
  TypeScript, lint, format, compilation, strict Credo and unused dependency checks pass.
- Chrome inspected API-only Telnyx on desktop and both-saved-fields on mobile. API-only
  public-key input has no placeholder; both-saved state masks both inputs. Screenshots
  saved to ignored tmp/onboarding-storybook/saved-placeholders-*.png.
- The prior full umbrella run remains at two unrelated backend timing failures; each
  affected file passed separately. No Elixir/backend code changed for this refinement.
- Preserved prior worktree changes. No commits or application-server management.

## Commit checkpoint

- User requested committing the accumulated scoped-service Storybook review. Reviewed
  exact pending paths and synchronized the plan's source-label, webhook-position and
  capability-warning descriptions with the final UI.
- Full frontend suite passes: 169 tests across 28 files, plus TypeScript and ESLint.
  Previous Storybook build and browser checks are recorded in this checkpoint's labnotes.
  The two known backend timing failures remain explicitly recorded; no claim of a green
  latest umbrella suite. No secrets, environment files, or generated artifacts staged.
