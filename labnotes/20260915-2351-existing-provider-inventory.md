# Existing provider inventory

## Decision and source evidence

- The user reiterated that this milestone must not add authentication for unsupported providers.
  `21c0b20` already narrowed the scope; this research makes checkpoint 5's provider list concrete.
- Compared reference tree `b5917ae` (before encrypted provisioning), current source and project
  tests. Google Gemini, Deepgram STT/TTS, Telnyx and Twilio have dedicated readers and tests.
- Zenmux is also demonstrated: `e9d3ab4` added an encoded native-routing request test, and the
  reference Engine `agent_model_profile_test.exs` constructs a real Zenmux ReqLLM configuration
  with nested routing/generation options. The Google-only inline catalog is an intermediate
  migration state; dropping Zenmux would remove a tested integration.
- No separate direct OpenAI/Anthropic/OpenRouter/Bedrock/Azure/Vertex authentication integration
  was demonstrated. Generic ReqLLM catalog acceptance and Zenmux's downstream model names do not
  create additional auth implementation tasks. Morse and fixtures stay credential-free.
- Added a durable inventory with per-provider evidence and current DB migration status. Replaced
  speculative milestone examples with Zenmux and removed context-compaction instructions for
  the deleted profile/global credential path. Explicitly marked Zenmux inline support pending.
- Checked off the inventory task only. Checkpoint 5 implementation has not started; the milestone
  still has 2 complete, 2 partial and 3 not started checkpoints.

## Verification

- Documentation-only research; no runtime change or new tests. The existing Telnyx provisioning
  root test run is running separately against `9c54f39`.
- Independent GPT 6 Astra xhigh source and documentation review found no missing demonstrated
  integration or scope/status blocker. Included its exact Zenmux nested-option contract and
  Deepgram/carrier metadata constraints; retained the explicit unrun live Zenmux limitation.
- All 174 local links/anchors resolve, the JSON example parses and all seven checkpoints remain.
  The index and milestone consistently retain 2 complete, 2 partial and 3 not started.
  `git diff --check` passes. Commit this reviewed documentation checkpoint separately.
