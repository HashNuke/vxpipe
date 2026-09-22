# Environment sample audit

Compared every `env.sample` setting with `config/runtime.exs`, `bin/dev`, the artifact S3 configuration, and the provider credential keyring. Provider API keys are stored in PostgreSQL rather than configured here. All retained variables have a current consumer or are standard AWS credentials used by ExAws.

The sample listed the lower-priority `DATABASE_URL` and `DB_POOL_SIZE` aliases beside their preferred `VXPIPE_DB_URL` and `VXPIPE_DB_POOL_SIZE` settings. It also listed four TLS variables that `bin/dev --tailscale` sets automatically. Removed those six entries from the starter file; runtime support for existing deployments and direct Mix launches remains unchanged.

Clarified that the encryption keyring is needed for encrypted provider credentials, `APP_HOST` is required in production but optional for local development, and `VXPIPE_RECORDING_ENABLED` enables development recording only. No application behavior changed.

Verification: parsed all 16 remaining sample names and confirmed a current runtime/script consumer for each, allowing for the ExAws standard AWS access-key pair. Confirmed the only uncommented assignments are placeholders, found no duplicate names, and passed `git diff --check`. The change is confined to the sample and this note, so it does not change runtime configuration or require the application test suite.
