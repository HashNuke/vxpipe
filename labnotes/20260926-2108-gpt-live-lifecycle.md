# GPT-Live post-reseed speech

Date: 2026-09-26. Starting revision: `4c707137`.

## Work and decisions

- The existing provider tests proved reseed commands and commentary, but E's
  post-reseed acceptance item also requires speech through the real STS
  capability. Added three fake-socket capability cases for a drop during an
  agent burst, after an unanswered caller turn, and while idle.
- The mid-burst case sends the disconnect immediately after the acknowledged
  audio event. This keeps the drop in the active burst without relying on a
  timer or sleep. It settles the first heard transcript before the replacement
  speaks. The idle case verifies no resume commentary before fresh caller
  audio; the unanswered case verifies the resume prompt and audible answer.
- All three cases passed with the existing implementation. No runtime change
  was needed. The Morse duplex provider still lacks scripted close events, so
  the lifecycle exit and transfer cases remain open.

## Verification

- Focused `mix test test/vxpipe/call_engine/capability/gpt_live_fake_socket_test.exs --seed 963322`
  from the CallEngine child: 16 tests, zero failures.
- From the umbrella root, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix deps.unlock --check-unused`, and `bin/verify-lean` passed. The initial
  format check identified two spacing changes in the new test; after formatting
  the file, the format check passed. `PGHOST=/var/run/postgresql mix test` passed
  2,843 tests with zero failures and 59 tagged exclusions.
