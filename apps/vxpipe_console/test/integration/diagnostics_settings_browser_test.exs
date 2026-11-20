defmodule Vxpipe.Console.DiagnosticsSettingsBrowserTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest

  alias Vxpipe.Persistence.{DiagnosticsSettingsStore, Repo}
  alias Vxpipe.Persistence.Schema.{IdentityRole, IdentityUser}

  @endpoint Vxpipe.Console.Endpoint
  @moduletag :integration
  @moduletag timeout: 120_000
  @moduletag :capture_log
  @email "diagnostics-browser@example.test"
  @password "Synthetic browser password 15!"

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    dependencies = %{
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: Vxpipe.Persistence.IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      installations: Vxpipe.Persistence.IdentityInstallationStore,
      diagnostics_settings: DiagnosticsSettingsStore,
      attempts: Vxpipe.Persistence.IdentityAttemptStore,
      audit: Vxpipe.Persistence.IdentityAuditStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }

    for {app, key, value} <- [
          {:vxpipe_identity, :dependencies, dependencies},
          {:vxpipe_console, :user_identity_backend, nil}
        ] do
      previous = Application.get_env(app, key)
      set_env(app, key, value)
      on_exit(fn -> set_env(app, key, previous) end)
    end

    proof =
      case Vxpipe.Identity.Bootstrap.status(dependencies) do
        {:ok, :pending_first_run} ->
          nil

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} =
            Vxpipe.Persistence.IdentityInstallationStore.issue_setup_proof(900)

          proof
      end

    assert build_conn()
           |> post("http://localhost/auth/api/setup", %{
             "email" => @email,
             "password" => @password,
             "password_confirmation" => @password,
             "public_url" => "http://localhost:4000",
             "proof" => proof
           })
           |> json_response(200) == %{"ok" => true}

    server = start_supervised!({Bandit, plug: @endpoint, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    session = "diagnostic-settings-#{System.unique_integer([:positive])}"
    on_exit(fn -> browser(session, ["close"]) end)
    %{origin: "http://127.0.0.1:#{port}", session: session}
  end

  for kind <- ["admin", "superadmin"] do
    @kind kind
    test "#{kind} saves, reloads and resolves conflicts in the production settings page", c do
      role = Repo.get_by!(IdentityRole, kind: @kind)
      user = Repo.get_by!(IdentityUser, normalized_email: @email)
      Repo.update!(Ecto.Changeset.change(user, role_id: role.id))
      command = &browser(c.session, &1)

      command.(["--args", "--no-sandbox", "open", c.origin <> "/auth/login"])
      command.(["set", "viewport", "1440", "1000"])
      command.(["find", "label", "Email", "fill", @email])
      command.(["find", "label", "Password", "fill", @password])
      command.(["find", "role", "button", "click", "--name", "Sign in", "--exact"])
      command.(["wait", "--fn", "!location.pathname.startsWith('/auth/')"])
      command.(["open", c.origin <> "/platform/installation"])
      wait_toggle(command, false)

      if @kind == "superadmin" do
        # URL settings load independently from the Diagnostics section.
        command.(["wait", "input[type=url]"])
      else
        refute command.(["eval", "!!document.querySelector('input[type=url]')"])
      end

      command.(["focus", "input[type=checkbox]"])
      command.(["press", "Space"])
      wait_toggle(command, true)
      assert {:ok, %{enabled: true, revision: 1}} = DiagnosticsSettingsStore.snapshot()
      command.(["reload"])
      wait_toggle(command, true)

      refute command.(["eval", "!!document.querySelector('#benchmark-setting-status')"])

      desktop = screenshot(command, c.session <> "-desktop")
      command.(["focus", "input[type=checkbox]"])
      command.(["press", "Space"])
      wait_toggle(command, false)
      assert {:ok, %{enabled: false, revision: 2}} = DiagnosticsSettingsStore.snapshot()
      command.(["reload"])
      wait_toggle(command, false)

      # A real second write advances the database while this rendered control
      # retains revision 2. The following UI save must conflict, not overwrite it.
      assert %{"status" => 200, "body" => %{"enabled" => true, "revision" => 3}} =
               command.([
                 "eval",
                 """
                 (async()=>{const r=await fetch('/api/installation/diagnostics',{
                   method:'PATCH',headers:{'content-type':'application/json',
                     'x-csrf-token':document.querySelector('meta[name=csrf-token]').content},
                   body:JSON.stringify({enabled:true,revision:2})});
                   return {status:r.status,body:await r.json()};})()
                 """
               ])

      command.(["focus", "input[type=checkbox]"])
      command.(["press", "Space"])

      command.([
        "wait",
        "--fn",
        "document.querySelector('[role=alert]')?.textContent.includes('changed elsewhere')"
      ])

      assert command.(["eval", "document.querySelector('input[type=checkbox]').disabled"])
      assert {:ok, %{enabled: true, revision: 3}} = DiagnosticsSettingsStore.snapshot()
      command.(["set", "viewport", "390", "844"])
      conflict = screenshot(command, c.session <> "-conflict")

      command.(["focus", "a.navigation-skip"])

      assert Enum.any?(1..20, fn _ ->
               command.(["press", "Tab"])

               command.([
                 "eval",
                 "document.activeElement.tagName==='BUTTON' && document.activeElement.textContent.trim()==='Reload diagnostics settings'"
               ])
             end)

      command.(["press", "Enter"])
      wait_toggle(command, true)
      command.(["focus", "input[type=checkbox]"])
      command.(["press", "Space"])
      wait_toggle(command, false)
      command.(["reload"])
      wait_toggle(command, false)
      assert {:ok, %{enabled: false, revision: 4}} = DiagnosticsSettingsStore.snapshot()
      refute command.(["eval", "document.documentElement.scrollWidth > innerWidth"])
      mobile = screenshot(command, c.session <> "-mobile")

      # A real store failure is isolated to this test's transaction.
      Repo.query!("DELETE FROM installation_diagnostics_settings")
      command.(["focus", "input[type=checkbox]"])
      command.(["press", "Space"])

      command.([
        "wait",
        "--fn",
        "document.querySelector('[role=alert]')?.textContent.includes('Could not confirm')"
      ])

      assert command.(["eval", "document.querySelector('input[type=checkbox]').disabled"])
      refute command.(["eval", "document.querySelector('input[type=checkbox]').checked"])

      IO.puts(
        "DIAGNOSTICS_BROWSER " <>
          JSON.encode!(%{role: @kind, desktop: desktop, conflict: conflict, mobile: mobile})
      )
    end
  end

  defp wait_toggle(command, enabled) do
    command.([
      "wait",
      "--fn",
      "(()=>{const e=document.querySelector('input[type=checkbox]');return !!e && !e.disabled && e.checked===#{enabled};})()"
    ])
  end

  defp screenshot(command, name) do
    path = Path.join(System.tmp_dir!(), "vxpipe-#{name}.png")
    command.(["screenshot", path])
    path
  end

  defp browser(session, arguments) do
    executable = System.find_executable("agent-browser") || raise "agent-browser is required"
    setsid = System.find_executable("setsid") || raise "setsid is required"

    {output, status} =
      System.cmd(setsid, ["--wait", executable, "--session", session, "--json" | arguments],
        stderr_to_stdout: true,
        env: [{"AGENT_BROWSER_DEFAULT_TIMEOUT", "15000"}]
      )

    case {status, JSON.decode(output)} do
      {0, {:ok, %{"success" => true, "data" => data}}} -> Map.get(data, "result", data)
      _ -> raise "Browser #{hd(arguments)} failed: #{output}"
    end
  end

  defp set_env(app, key, nil), do: Application.delete_env(app, key)
  defp set_env(app, key, value), do: Application.put_env(app, key, value)
end
