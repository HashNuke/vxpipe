defmodule Vxpipe.Persistence.IdentityMigrationAcceptanceTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  @pre_auth_version "20261013000100"
  @child_dir Path.expand("../..", __DIR__)

  test "fresh migration allows first-run setup and survives a fresh VM login" do
    with_disposable_database("fresh", fn database ->
      migrate(database)

      assert query(
               database,
               "SELECT bootstrap_mode FROM authentication_installations WHERE key = 'default'"
             ) == "first_run"

      run_mix!(database, ["run", "-e", setup_expression(:first_run)])
      run_mix!(database, ["run", "-e", login_after_restart_expression()])
    end)
  end

  test "tenant-only pre-auth installation requires trusted setup proof and preserves tenant" do
    with_disposable_database("tenant", fn database ->
      migrate_pre_auth(database)
      seed_tenant(database)
      migrate(database)

      assert query(
               database,
               "SELECT bootstrap_mode FROM authentication_installations WHERE key = 'default'"
             ) == "operator_required"

      assert query(database, "SELECT count(*) FROM tenants WHERE key = 'abcdefghijklmnop'") == "1"
      run_mix!(database, ["run", "-e", setup_expression(:operator_required)])
      run_mix!(database, ["run", "-e", login_after_restart_expression()])
    end)
  end

  test "populated pre-auth installation retains demo, tenant key, operator key, spec and challenge" do
    with_disposable_database("populated", fn database ->
      migrate_pre_auth(database)
      seed_tenant(database)

      query(
        database,
        "INSERT INTO installation_setups (key, demo_tenant_id, inserted_at) SELECT 'demo', id, now() FROM tenants WHERE key = 'abcdefghijklmnop'"
      )

      query(
        database,
        "INSERT INTO api_keys (public_id, tenant_id, name, scopes, digest, inserted_at, updated_at) SELECT gen_random_uuid(), id, 'existing', ARRAY['admin']::varchar[], decode(repeat('bb', 32), 'hex'), now(), now() FROM tenants WHERE key = 'abcdefghijklmnop'"
      )

      query(
        database,
        "INSERT INTO operator_api_keys (public_id, digest, inserted_at, updated_at) VALUES (gen_random_uuid(), decode(repeat('aa', 32), 'hex'), now(), now())"
      )

      query(
        database,
        "INSERT INTO call_specs (tenant_id, public_id, inserted_at, updated_at) SELECT id, 'existing-spec', now(), now() FROM tenants WHERE key = 'abcdefghijklmnop'"
      )

      query(
        database,
        "INSERT INTO operator_login_challenges (token_digest, code_verifier, issued_at, expires_at) VALUES (decode(repeat('cc', 32), 'hex'), decode(repeat('dd', 32), 'hex'), now(), now() + interval '15 minutes')"
      )

      migrate(database)

      assert query(
               database,
               "SELECT bootstrap_mode FROM authentication_installations WHERE key = 'default'"
             ) == "operator_required"

      for table <- [
            "tenants",
            "installation_setups",
            "api_keys",
            "operator_api_keys",
            "call_specs",
            "operator_login_challenges"
          ] do
        assert query(database, "SELECT count(*) FROM #{table}") == "1", table
      end

      run_mix!(database, ["run", "-e", setup_expression(:operator_required)])
      run_mix!(database, ["run", "-e", login_after_restart_expression()])
    end)
  end

  test "a session revoked in another BEAM is denied by the original long-lived BEAM" do
    with_disposable_database("revocation", fn database ->
      migrate(database)
      run_mix!(database, ["run", "-e", setup_expression(:first_run)])

      port = start_authentication_beam(database)

      try do
        user_public_id = await_port_marker(port, "READY:")
        assert String.match?(user_public_id, ~r/\A[0-9a-f-]{36}\z/)

        Port.command(port, "AUTH\n")
        assert await_port_marker(port, "AUTH:") == "ok"

        run_mix!(database, [
          "run",
          "-e",
          "#{start_repo_expression()} {:ok, count} = Vxpipe.Persistence.IdentitySessionStore.revoke_for_user(#{inspect(user_public_id)}, DateTime.utc_now()); true = count > 0"
        ])

        Port.command(port, "AUTH\n")
        assert await_port_marker(port, "AUTH:") == "revoked"
      after
        if Port.info(port) != nil, do: Port.close(port)
      end
    end)
  end

  defp with_disposable_database(label, callback) do
    database = "vxpipe_auth_accept_#{label}_#{System.unique_integer([:positive])}"
    command!("createdb", [database])
    on_exit(fn -> command!("dropdb", ["--if-exists", database]) end)
    callback.(database)
  end

  defp migrate_pre_auth(database),
    do: run_mix!(database, ["ecto.migrate", "--to-exclusive", @pre_auth_version, "--quiet"])

  defp migrate(database), do: run_mix!(database, ["ecto.migrate", "--quiet"])

  defp seed_tenant(database) do
    query(
      database,
      "INSERT INTO tenants (key, name, inserted_at, updated_at) VALUES ('abcdefghijklmnop', 'Existing tenant', now(), now())"
    )
  end

  defp query(database, sql) do
    command!("psql", ["-X", "-v", "ON_ERROR_STOP=1", "-d", database, "-Atqc", sql])
    |> String.trim()
  end

  defp run_mix!(database, arguments) do
    arguments =
      if List.first(arguments) == "run",
        do: ["run", "--no-start" | tl(arguments)],
        else: arguments

    command!("mix", arguments,
      cd: @child_dir,
      env: [
        {"MIX_ENV", "test"},
        {"VXPIPE_TEST_DATABASE_URL", nil},
        {"VXPIPE_TEST_DATABASE", database}
      ]
    )
  end

  defp start_authentication_beam(database) do
    expression =
      "#{start_repo_expression()} deps = #{deps_expression()}; " <>
        "{:ok, %{token: token}} = Vxpipe.Identity.Sessions.login(deps, \"root@example.com\", \"correct horse 15!\", \"127.0.0.1\"); " <>
        "{:ok, principal} = Vxpipe.Identity.Sessions.authenticate(deps, token); IO.puts(\"READY:\" <> principal.user_public_id); " <>
        "loop = fn recur -> case IO.gets(:stdio, \"\") do \"AUTH\\n\" -> result = Vxpipe.Identity.Sessions.authenticate(deps, token); marker = case result do {:ok, _} -> \"ok\"; {:error, :revoked} -> \"revoked\"; _ -> \"unexpected\" end; IO.puts(\"AUTH:\" <> marker); recur.(recur); _ -> :ok end end; loop.(loop)"

    executable = System.find_executable("mix") || flunk("mix executable unavailable")

    Port.open({:spawn_executable, String.to_charlist(executable)}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      {:line, 4096},
      {:cd, String.to_charlist(@child_dir)},
      {:args,
       Enum.map(["run", "--no-start", "--no-compile", "-e", expression], &String.to_charlist/1)},
      {:env,
       [
         {~c"MIX_ENV", ~c"test"},
         {~c"VXPIPE_TEST_DATABASE_URL", false},
         {~c"VXPIPE_TEST_DATABASE", String.to_charlist(database)}
       ]}
    ])
  end

  defp await_port_marker(port, prefix) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        if String.starts_with?(line, prefix) do
          String.replace_prefix(line, prefix, "")
        else
          await_port_marker(port, prefix)
        end

      {^port, {:data, {:noeol, _line}}} ->
        await_port_marker(port, prefix)

      {^port, {:exit_status, status}} ->
        flunk("authentication BEAM exited early with status #{status}")
    after
      60_000 -> flunk("authentication BEAM did not respond with #{prefix}")
    end
  end

  defp command!(program, arguments, options \\ []) do
    {output, status} =
      System.cmd(program, arguments, Keyword.merge([stderr_to_stdout: true], options))

    if status == 0, do: output, else: flunk("#{program} failed (#{status}):\n#{output}")
  end

  defp setup_expression(mode) do
    common =
      "#{start_repo_expression()} deps = #{deps_expression()}; "

    flow =
      case mode do
        :first_run ->
          "{:ok, %{token: token}} = Vxpipe.Identity.Bootstrap.complete_first_run(deps, \"root@example.com\", \"correct horse 15!\", \"correct horse 15!\"); "

        :operator_required ->
          "{:error, :proof_required} = Vxpipe.Identity.Bootstrap.complete_first_run(deps, \"root@example.com\", \"correct horse 15!\", \"correct horse 15!\"); {:ok, %{proof: proof}} = Vxpipe.Persistence.IdentityInstallationStore.issue_setup_proof(900); {:ok, %{token: token}} = Vxpipe.Identity.Bootstrap.complete_with_proof(deps, proof, \"root@example.com\", \"correct horse 15!\", \"correct horse 15!\"); "
      end

    common <>
      flow <>
      "{:ok, _} = Vxpipe.Identity.Sessions.authenticate(deps, token); {:ok, :complete} = Vxpipe.Identity.Bootstrap.status(deps)"
  end

  defp login_after_restart_expression do
    "#{start_repo_expression()} deps = #{deps_expression()}; {:ok, :complete} = Vxpipe.Identity.Bootstrap.status(deps); {:ok, %{token: token}} = Vxpipe.Identity.Sessions.login(deps, \"root@example.com\", \"correct horse 15!\", \"127.0.0.1\"); {:ok, _} = Vxpipe.Identity.Sessions.authenticate(deps, token); {:error, :already_completed} = Vxpipe.Identity.Bootstrap.complete_first_run(deps, \"other@example.com\", \"correct horse 15!\", \"correct horse 15!\")"
  end

  defp start_repo_expression do
    "Application.put_env(:vxpipe_persistence, :enabled, true); {:ok, _} = Application.ensure_all_started(:vxpipe_persistence); Ecto.Adapters.SQL.Sandbox.mode(Vxpipe.Persistence.Repo, :auto);"
  end

  defp deps_expression do
    "%{users: Vxpipe.Persistence.IdentityUserStore, roles: Vxpipe.Persistence.IdentityRoleStore, sessions: Vxpipe.Persistence.IdentitySessionStore, installations: Vxpipe.Persistence.IdentityInstallationStore, audit: Vxpipe.Persistence.IdentityAuditStore, attempts: Vxpipe.Persistence.IdentityAttemptStore, hasher: Vxpipe.Identity.Argon2Hasher, tokens: Vxpipe.Identity.Tokens, clock: Vxpipe.Identity.Clock, uuid: Vxpipe.Identity.Uuid}"
  end
end
