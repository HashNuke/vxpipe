# OpenAI reseed wire

## Failure and repair

- Selected hosted reseeding reached the real provider but rejected assistant
  history. Shared published history uses `input_text`; OpenAI's GPT-Live startup
  protocol requires assistant content to use `output_text`.
- Add a focused codec regression first, then translate assistant message content
  only at the provider wire boundary. Keep user input and the shared history
  representation unchanged. Update exact wire assertions in the session and
  fake-socket capability tests.
- Add a stopped-transport reseed test which acknowledges the consumer history
  barrier. A bounded 1000ms test startup acknowledgement replaces a 100ms default
  that failed under concurrent load; runtime deadlines remain unchanged.

## Evidence and limits

- The codec regression failed before the translation and passed afterward.
- The repaired session and fake-socket capability group passes 41 tests.
- Selected hosted reseed/mute/talkover passed individually in 12.7 seconds;
  delegated-tool continuation passed separately in 7.3 seconds. The hosted test
  repairs, model selection and request bounds are recorded with the live lane.
- No additional live request was needed for this commit. Full umbrella acceptance
  remains pending; this codec repair does not complete phone or new speech
  provider acceptance.

Primary protocol evidence:
https://developers.openai.com/api/docs/guides/live-conversations.
