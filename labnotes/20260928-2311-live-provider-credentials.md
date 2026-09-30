# Live provider credentials and Deepgram samples

2026-09-28. The live-provider lane now uses one opt-in runner,
`bin/test-live-providers`, with Mix arguments forwarded unchanged. It loads
`~/.config/vxpipe/live_providers.env` only for the child test process and clears
ambient provider credentials first. The committed template lists all current
AI and telephony variables with `todo` values and `https://todo` URL
placeholders. The runner treats unchanged placeholders as missing settings;
the shell contract failed before this change and passed after it. S3 was
removed from this lane because its network behavior belongs to ExAws rather
than the telephony/AI provider contract.

The selected Deepgram live tests now call
`Vxpipe.Providers.Deepgram.LiveFixture` from provider test support. The helper
uses a fixed short phrase, makes one TTS request if raw PCM is absent, and uses
FFmpeg to derive Opus if absent. It retains generated files in the provider
test fixture directory for review and later commit. Existing files avoid
repeat generation. The generated audio and the hosted Flux tail have not been
validated with a live key here.
The OpenAI/Gemini/Zenmux/Deepgram/Twilio/Telnyx groups remain excluded from
ordinary `mix test`.

The runner shell contract passed with a fake Mix binary. Direct ExUnit
execution of the provider fixture helper's three tests passed (3/0). This
standalone invocation warned that Req was unavailable because it did not
load Mix dependencies. `mix test`, compilation, Credo and the unused-dependency
check could not start: Mix.PubSub failed to open its local TCP socket with
`:eperm` in this sandbox. `mix format --check-formatted` and
`git diff --check` passed. No live provider call was made. The unrelated
worktree change in `vxpipe-docs/src/content.config.ts` was preserved.
