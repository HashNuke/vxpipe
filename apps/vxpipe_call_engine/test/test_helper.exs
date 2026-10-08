# Releases preload every module at boot; the test VM loads them lazily, so the first test to
# exercise a code path (such as room startup) pays for code loading inside its time-bounded
# assertions. Preload the same way production does.
for {app, _description, _version} <- Application.loaded_applications(),
    modules = Application.spec(app, :modules),
    is_list(modules) do
  Code.ensure_all_loaded(modules)
end

# Billed long sessions are selected only through their explicit long tags.
ExUnit.start(exclude: [:integration, :live_providers, :live_long])
