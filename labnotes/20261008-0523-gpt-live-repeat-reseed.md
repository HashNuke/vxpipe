# GPT-Live: allow reseeding more than once in a long call

## Question

After fixing Gemini Live session longevity, check whether GPT-Live has the same kind of
problem, and whether it needs context compaction.

## Findings

- OpenAI's GPT-Live session guide: the 128k-token context is compacted by the service itself
  (a replacement voice engine with instructions, recent history and a summary once usage
  exceeds 90%). There is no compaction or truncation setting to enable. The truncation fields
  in the voice cost guide belong to the older Realtime API.
- Sessions can still end with `expired` (no documented duration) or `connection_lost`. The
  adapter has no fixed renewal or expiry timers and never refuses caller audio while waiting,
  unlike the Gemini adapter before `8481ceb9`.
- Defect: on `expired`/`connection_lost` the adapter reseeds from published history, but
  `reseed_attempted?` was set and never cleared, so a second loss at any later point ended the
  call with `:reseed_failed`.

## Change

Red test first ("a replacement that completed an exchange can be reseeded after a later drop":
no third connection started). The flag now clears when an agent output completes on a ready
session (`GPTLiveOutput.maybe_complete/3`). A replacement that drops before completing an output
still fails, so repeated immediate failures cannot loop. Verified: the GPT-Live capability and
provider suites pass 63 tests; root gates recorded in the commit.

Not done: surfacing `session.usage.updated` `context_window.usage_ratio` (optional observability).
