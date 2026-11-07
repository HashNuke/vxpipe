# `live_long` tests are billed long sessions; only their own tags select them.
# Hosted catalog tests use only their live tag: --include integration must not select them.
ExUnit.start(exclude: [:integration, :live_providers, :live_long, :live_integrations_directory])
