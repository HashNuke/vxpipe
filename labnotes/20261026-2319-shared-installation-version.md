# Shared installation version

- Reviewed the existing version change as its own configuration checkpoint.
  Root and all ten umbrella children read the same root VERSION file.
- The version stays 0.1.0. Running releases obtain it from the owning OTP
  application's metadata; the umbrella is not itself an OTP application.
- Storybook and Vitest inject that same value at build time, preparing directory
  requests without adding runtime environment reads or network calls.
- Checked every child mix.exs path and the Storybook/Vitest paths. TypeScript,
  compilation with warnings as errors, and the full frontend suite pass.
- Directory protocol examples and request-builder tests are kept with the later
  directory checkpoint that introduces their consumers.
