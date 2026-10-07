# `live_long` tests are billed long sessions; only their own tags select them.
ExUnit.start(exclude: [:integration, :live_providers, :live_long])
