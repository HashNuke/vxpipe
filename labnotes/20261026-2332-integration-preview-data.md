# Integration preview data

- Split the directory request/response models, provider/MCP catalog fixtures, and
  authentication draft validation into a prerequisite checkpoint for the reviewed
  Storybook workflow. These modules make no network requests or durable writes.
- Requests carry the shared build version, omit category for global search, and
  use the deployed `category` query parameter. The simulated API applies scope and
  compatibility filters before pagination and preserves opaque cursor identity.
- Optional MCP setup notes and links match the external definitions/API contract.
  Saved preview connections retain authentication choices without retaining secret
  values; the consuming management UI and its regression coverage follow separately.
- Verification: the three header-casing fixture tests pass; the complete working
  tree passed 915 frontend tests, TypeScript, and a Storybook build. The later UI
  checkpoint records the interaction and rendered-browser evidence.
