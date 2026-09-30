# Speech live credentials

## Boundary preparation

Cartesia and ElevenLabs speech integrations are pending, but their supplied
credentials must follow the runner's existing child-process isolation contract.
Add both names to the fixed credential list and add `todo` template entries
explicitly labelled as integrations in progress. No new provider capability,
live test module or request is introduced.

## Red and green

- Extend the fake-Mix shell contract to observe these synthetic inputs. It fails
  on the original runner with `CARTESIA_API_KEY placeholder was not cleared`.
- After adding both names, placeholders are removed, file-provided ElevenLabs
  material reaches only the child, and ambient keys are absent when the fake
  configuration omits them. The shell contract and Bash syntax checks pass.
- The tests use a temporary fake configuration and fake Mix. The private live
  credential file is neither read nor modified, and no billable request occurs.

## Remaining acceptance

The same-seed root run now passes all 1683 CallEngine tests, but Gateway exposed
an intermittent `after_speech_adoption` preparation timeout while waiting for a
second progress notification. Its cause is not established. Preserve this as an
open acceptance failure rather than claiming a green umbrella or weakening the
handoff assertion. New speech capabilities also remain unimplemented.
