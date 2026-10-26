# Breadcrumb navigation foundation

- Reviewed the shared opt-in Storybook breadcrumb components and their use in call
  details, call-spec editor, API key forms, and account administration forms.
- Live pages retain existing defaults when no StoryNavigationContext is supplied.
  Editor breadcrumb links use the existing unsaved-change guard before leaving.
- Keep the workspace shell and integration category wiring in the subsequent
  integration workflow checkpoint; these shared primitives do not import it.
- Focused editor regression covers the guarded tenant breadcrumb. Call-details
  assertions now expect the tenant-first trail. The auth test waits for role loading
  to finish before Save, preserving the existing production behavior.
- These presentation changes require no backend data-contract changes. The full
  frontend suite and TypeScript passed during review; rendered breadcrumb evidence
  is recorded in the existing tenant-page-breadcrumbs labnote.
