# Opt-in live provider tests

Status: design and inventory recorded 2026-09-27. Current live modules use
Mix tags for selection, with `:live_providers` excluded by default. The
configured-service harness described below remains implementation work. No
live service was called for this checkpoint.

## Decision

Keep three test boundaries with different evidence:

| Boundary | Credential source | Runs by default | Proves |
| --- | --- | --- | --- |
| Local contract and service selection | Synthetic encrypted test records and fake transports | Yes, where existing suites allow it | Tenant credential precedence, platform inheritance, missing or unreadable tenant failure, authorization, and protocol decisions |
| Live provider protocol | A secret supplied to the test process | No | The actual provider accepts the adapter's wire format and returns the expected events |
| Live configured service | Dedicated test tenant and platform service records resolved through the production credential source | No | A call using the selected service reaches the real provider through the normal application path |

The second boundary belongs in the app that owns the provider adapter. It may
use an environment variable or secret manager as test input because it is
testing the provider protocol in isolation. It must not claim that tenant or
platform credential resolution was exercised. The third boundary must start
from a call spec or service binding and use
`Vxpipe.Calls.ProviderCredentialSource` or the corresponding telephony service
reader. It must not pass a raw test key directly to the provider adapter.
This preserves the umbrella's dependency direction: lower-level provider and
agent-runtime tests do not import Persistence just to test service selection.

The current service rule is exact provider/name selection: an existing tenant
credential wins; otherwise the platform credential is used. An inactive or
unreadable tenant credential fails closed and does not fall back. Local
[`ScopedProviderCredentialsTest`](../apps/vxpipe_persistence/test/vxpipe/persistence/scoped_provider_credentials_test.exs)
already proves these choices without paying for duplicate remote calls. A
live configured-service test should assert the resolved owner and credential
identity before its short provider operation. Run both sources against the
real provider only when a specific source-path integration risk warrants the
additional call.

## Selection and authorization

Use Mix/ExUnit's built-in tag filters. Every test that contacts a third-party
service gets `@moduletag :live_providers` and a provider tag such as
`@moduletag :live_openai`. Every child test helper excludes `:live_providers`
from ordinary `mix test`. Live modules do not carry `:integration`, so a broad
`--include integration` selection cannot include them. The Mix filter is the
explicit selection; no additional run flag is required.

With required credentials and test settings already available to the process,
run all current live groups from the umbrella root by naming the four owning
test directories:

```shell
mix test --only live_providers \
  apps/vxpipe_agent_runtime/test/integration \
  apps/vxpipe_artifacts/test/integration \
  apps/vxpipe_call_engine/test/integration \
  apps/vxpipe_gateway/test/integration
```

To run only OpenAI, select its provider tag:

```shell
mix test --only live_openai \
  apps/vxpipe_call_engine/test/integration/gpt_live_hosted_test.exs
```

The explicit paths matter in an umbrella: `--only live_providers` against a
child with no matching tests exits with a no-tests result. From an owning child
directory, the same filters work without an umbrella path. When selected
without a required credential or fixture setting, the test should fail clearly
before contacting the provider. CI and the default suite do not select live
tags or inject live credentials.

Use a dedicated provider test project or account with an explicit spend limit
where the provider supports one. Supply keys through the shell environment or
a secret manager, never in a call spec fixture, committed file, command-line
argument, log, or test failure. OpenAI's
[production guidance](https://developers.openai.com/api/docs/guides/production-best-practices)
recommends environment variables or a secret manager instead of hard-coded
keys, and describes project spend limits. Each live test defines its maximum
sessions, input/audio duration, timeout, destination allowlist where relevant,
and retry policy. Record sanitized provider, model, credential scope, result,
and measured usage; do not retain raw authorization, audio, or transcripts.

## Configured-service fixture

For automated tests, provision a dedicated temporary tenant and the chosen
tenant or platform credential into the isolated test database through the
public administration path. A secret environment variable is only the input
to that encrypted provisioning step. The test then resolves and starts the
call through normal application readers. Use a distinct credential name and
test tenant, and clean up with the test sandbox. This is separate from the
provider-protocol test, which does not need a database.

Real carrier phone acceptance needs a reachable staging deployment, a
configured test number and application/webhook binding, and a person on the
phone. The configured service in that deployment is the source of truth;
the local Mix test database is not the deployment's credential store. The
manual observations stay in the milestone labnotes. Do not claim phone
interoperability from a direct WebSocket protocol test.

## Existing inventory and migration order

1. Add group and provider-specific live tags to current OpenAI, Deepgram,
   Gemini, Zenmux, Twilio, Telnyx, and S3 live modules, and exclude the group
   tag in every child test helper.
   Keep local HTTP, database, fake-socket, conformance, and loopback integration
   modules out of the live group. Keep `:integration` for local integration
   tests. Completed for the current inventory.
2. Verify ordinary `mix test` and `--include integration` exclude live modules.
   Verify `--only live_providers` and `--only live_<provider>` select the
   intended files. Verify missing secrets fail clearly after selection.
3. Add a test-only configured-service fixture at the Calls/Persistence
   boundary. Prove the fixture selects a tenant override and platform fallback
   with fake transports before any live use, then add one bounded real-provider
   call through a published test call spec.
4. Use the opt-in GPT-Live protocol lane and a configured Twilio or Telnyx
   phone leg for the remaining
   [GPT-Live milestone](milestones/gpt-live-speech-to-speech.md) acceptance.
   Record the six residual observations in
   [the duplex profile](sts-duplex-profile.md) and keep the milestone open
   until the authorized live and phone checks pass.

## Alternatives rejected

- Running all `:integration` tests for provider checks mixes local integration
  with billable calls and makes cost hard to see.
- An extra environment run gate duplicated Mix selection and made a selected
  test silently skip; the dedicated live tag is sufficient for opt-in.
- Passing environment keys straight to an end-to-end provider test bypasses
  the tenant/platform source contract that the test claims to verify.
- Forcing every low-level adapter test through a database would add an
  unrelated Persistence dependency and duplicate service-selection tests.
- Using the production tenant or platform database from `MIX_ENV=test` would
  make tests change live configuration and lose isolation.

## Verification evidence

Local `mix help test` documents `--include`, `--exclude`, and `--only`. With
`OPENAI_API_KEY` explicitly unset, both ordinary `mix test` and `--include
integration` excluded the two OpenAI tests. `--only live_openai` selected both;
they failed at `System.fetch_env!/1` before a provider connection. `--only
live_providers` selected the same two tests on that file and also stopped at
the missing-key check. The group and provider tags cover 14 current live tests
across AgentRuntime (4), Artifacts (1), CallEngine (4), and Gateway (5). A child
without matching tags exits with no tests under `--only`; this is why the
umbrella command names the owning paths. The configured-service fixture and
authorized live runs remain pending. Formatting, warnings-as-errors compilation,
strict Credo, and the unused-dependency check passed. The first umbrella run
had three timing failures in unchanged tests; each passed in a focused rerun.
A repeat root `mix test --max-cases 2` passed all 2,868 tests with zero failures.
