defmodule Vxpipe.Calls.TenantDirectoryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{InstallationOperator, Tenant, TenantDirectory, TestAdminRepository}
  alias Vxpipe.Calls.Principal, as: ApiPrincipal
  alias Vxpipe.Identity.Principal

  @key "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  test "discovery policy is available without querying storage for transport authorization" do
    key = %ApiPrincipal{tenant_key: @key, api_key_id: "key", scopes: MapSet.new([:calls])}
    assert :ok = Vxpipe.Calls.authorize_tenant_discovery(key)

    assert {:error, :forbidden} =
             Vxpipe.Calls.authorize_tenant_discovery(%{key | scopes: MapSet.new()})

    assert :ok = Vxpipe.Calls.authorize_tenant_discovery(principal())

    assert {:error, :forbidden} =
             Vxpipe.Calls.authorize_tenant_discovery(principal(%{grants: MapSet.new()}))
  end

  test "all-tenant authority has precedence and requires no directory query" do
    for user <- [
          principal(%{account_kind: :admin}),
          principal(%{all_tenant_actions: MapSet.new(["calls.read"])})
        ] do
      assert {:ok, %{scope: :all, landing_tenant: nil, directory_access: true}} =
               TenantDirectory.navigation(user, admin_repository: {__MODULE__, :must_not_call})
    end
  end

  test "landing examines at most two extant authorized tenants rather than assignment count" do
    user = principal(%{assigned_tenants: %{@key => :read, @other => :read}})
    opts = repository({:ok, [tenant(@key)]})

    assert {:ok, %{scope: :assigned, landing_tenant: %Tenant{key: @key}}} =
             TenantDirectory.navigation(user, opts)

    assert_received {:tenant_candidates, {:keys, [@key, @other]}, 2}

    for tenants <- [[], [tenant(@key), tenant(@other)]] do
      assert {:ok, %{landing_tenant: nil}} =
               TenantDirectory.navigation(user, repository({:ok, tenants}))
    end
  end

  test "no grants and installation tenants.read alone do not manufacture tenant access" do
    for grants <- [MapSet.new(), MapSet.new(["tenants.read"])] do
      user = principal(%{grants: grants})

      assert {:ok, %{scope: :assigned, landing_tenant: nil, directory_access: allowed}} =
               TenantDirectory.navigation(user, admin_repository: {__MODULE__, :must_not_call})

      assert allowed == MapSet.member?(grants, "tenants.read")
    end
  end

  test "storage failure and out-of-scope adapter results cannot become a landing" do
    assert {:error, :repository_unavailable} =
             TenantDirectory.navigation(
               principal(),
               repository({:error, :repository_unavailable})
             )

    assert {:error, :tenant_page_unavailable} =
             TenantDirectory.navigation(principal(), repository({:ok, [tenant(@other)]}))
  end

  test "selected tenant identity checks visible scope before reading persistence" do
    assert {:error, :tenant_not_found} = TenantDirectory.fetch(principal(), @other, [])
    assert {:error, :tenant_not_found} = TenantDirectory.fetch(principal(), "invalid", [])

    assert {:error, :tenant_not_found} =
             TenantDirectory.fetch(principal(), @key, repository({:ok, []}))

    assert {:ok, %Tenant{key: @key}} =
             TenantDirectory.fetch(principal(), @key, repository({:ok, [tenant(@key)]}))

    assert_received {:tenant_candidates, {:keys, [@key]}, 1}

    assert {:error, :tenant_page_unavailable} =
             TenantDirectory.fetch(principal(), @key, repository({:ok, [tenant(@other)]}))
  end

  test "search forwards bounded normalized query and scoped offset" do
    assert {:ok, page} =
             TenantDirectory.search(
               principal(),
               repository({:ok, {[tenant(@key)], 3}}) ++ [query: "  Acme  ", page: 2, limit: 2]
             )

    assert page.page_size == 2
    assert page.total == 3
    assert page.total_pages == 2
    assert_received {:tenant_search, {:keys, [@key]}, "Acme", 2, 2}
  end

  test "search rejects invalid bounds and conceals unauthorized results" do
    for options <- [
          [query: %{}],
          [query: String.duplicate("a", 121)],
          [limit: 51],
          [limit: 0],
          [page: -1],
          [page: 1.5]
        ] do
      assert {:error, :invalid_tenant_page_request} = TenantDirectory.search(principal(), options)
    end

    assert {:error, :tenant_page_out_of_range} =
             TenantDirectory.search(principal(), repository({:ok, {[], 0}}) ++ [page: 2])

    assert {:error, :tenant_page_unavailable} =
             TenantDirectory.search(principal(), repository({:ok, {[tenant(@other)], 1}}))

    assert {:error, :forbidden} = TenantDirectory.search(principal(%{grants: MapSet.new()}), [])

    assert {:ok, %{tenants: [], total: 0}} =
             TenantDirectory.search(principal(%{assigned_tenants: %{}}), [])
  end

  test "malformed adapter payloads fail closed rather than escaping as success" do
    for result <- [{:ok, :invalid}, {:ok, {[], -1}}, {:ok, {[], "1"}}, {:ok, {[tenant(@key)], 0}}] do
      assert {:error, :tenant_page_unavailable} =
               TenantDirectory.search(principal(), repository(result))
    end

    assert {:error, :tenant_page_unavailable} =
             TenantDirectory.navigation(principal(), repository({:ok, %{}}))
  end

  test "search normalizes before its character bound and rejects unrepresentable SQL inputs" do
    query = String.duplicate("é", 120)

    assert {:ok, _page} =
             TenantDirectory.search(
               principal(),
               repository({:ok, {[], 0}}) ++ [query: "  #{query}  "]
             )

    assert_received {:tenant_search, _, ^query, _, _}

    for options <- [[query: <<0>>], [query: <<255>>], [page: 10_000_000_000_000_000_000]] do
      assert {:error, :invalid_tenant_page_request} =
               TenantDirectory.search(principal(), repository({:ok, {[], 0}}) ++ options)
    end
  end

  test "tenant API keys discover only their own tenant without widening their scopes" do
    for scopes <- [[:calls], [:admin], [:admin, :calls]] do
      actor = api_principal(scopes)

      assert {:ok, %{tenants: [%Tenant{key: @key}], total: 1, page: 1, page_size: 25}} =
               TenantDirectory.search(actor, repository({:ok, {[tenant(@key)], 1}}))

      assert_received {:tenant_search, {:keys, [@key]}, "", 25, 0}

      assert {:ok, %Tenant{key: @key}} =
               TenantDirectory.fetch(actor, @key, repository({:ok, [tenant(@key)]}))

      assert_received {:tenant_candidates, {:keys, [@key]}, 1}
      assert {:error, :tenant_not_found} = TenantDirectory.fetch(actor, @other, [])

      assert {:error, :tenant_not_found} =
               TenantDirectory.fetch(actor, @key, repository({:ok, []}))
    end
  end

  test "Settings platform API keys use the shared bounded directory and lookup" do
    assert {:ok, %{tenants: [%Tenant{key: @other}], total: 3, total_pages: 2, page: 2}} =
             TenantDirectory.search(
               platform_actor(),
               repository({:ok, {[tenant(@other)], 3}}) ++
                 [page: 2, limit: 2, query: "  Tenant  "]
             )

    assert_received {:tenant_search, :all, "Tenant", 2, 2}

    assert {:ok, %Tenant{key: @other}} =
             TenantDirectory.fetch(platform_actor(), @other, repository({:ok, [tenant(@other)]}))

    assert_received {:tenant_candidates, {:keys, [@other]}, 1}
  end

  test "unknown, unscoped and legacy operator actors cannot discover tenants" do
    for actor <- [
          nil,
          %{grant: :installation_operator, credential_kind: :platform_api_key},
          api_principal([]),
          api_principal([:unknown]),
          %{api_principal([:calls]) | tenant_key: "invalid"},
          %{platform_actor() | credential_kind: :legacy_operator_api_key},
          %{platform_actor() | api_key_id: nil},
          InstallationOperator.authority()
        ] do
      assert {:error, :forbidden} = TenantDirectory.search(actor, [])
      assert {:error, :tenant_not_found} = TenantDirectory.fetch(actor, @key, [])
    end
  end

  test "API key discovery uses consistent empty pages, bounds and storage failures" do
    for actor <- [api_principal([:calls]), platform_actor()] do
      assert {:ok, %{tenants: [], total: 0, total_pages: 0}} =
               TenantDirectory.search(actor, repository({:ok, {[], 0}}))

      assert {:error, :tenant_page_out_of_range} =
               TenantDirectory.search(actor, repository({:ok, {[], 0}}) ++ [page: 2])

      assert {:error, :invalid_tenant_page_request} =
               TenantDirectory.search(actor, limit: 51)

      assert {:error, :repository_unavailable} =
               TenantDirectory.search(actor, repository({:error, :repository_unavailable}))

      assert {:error, :repository_unavailable} =
               TenantDirectory.fetch(actor, @key, repository({:error, :repository_unavailable}))
    end
  end

  test "API key discovery rejects repository rows outside scope or beyond the requested page" do
    actor = api_principal([:calls])

    assert {:error, :tenant_page_unavailable} =
             TenantDirectory.search(actor, repository({:ok, {[tenant(@other)], 1}}))

    assert {:error, :tenant_page_unavailable} =
             TenantDirectory.fetch(actor, @key, repository({:ok, [tenant(@other)]}))

    assert {:error, :tenant_page_unavailable} =
             TenantDirectory.search(
               platform_actor(),
               repository({:ok, {[tenant(@key), tenant(@other)], 2}}) ++ [limit: 1]
             )
  end

  test "dashboard omits unauthorized recent calls and treats failed calls as a partial failure" do
    opts = [
      admin_repository: {Vxpipe.Calls.TestDashboardRepository, {self(), tenant(@key), {:ok, []}}}
    ]

    keys_only = principal(%{grants: MapSet.new(["tenant_services.read"])})
    assert {:ok, dashboard} = Vxpipe.Calls.TenantDashboard.fetch(keys_only, @key, opts)
    refute Map.has_key?(dashboard, :recent_calls)
    refute_received {:recent_calls, _, _}

    assert {:ok, %{recent_calls: %{status: :ready, calls: []}}} =
             Vxpipe.Calls.TenantDashboard.fetch(principal(), @key, opts)

    assert_received {:recent_calls, @key, 5}

    unavailable = [
      admin_repository:
        {Vxpipe.Calls.TestDashboardRepository,
         {self(), tenant(@key), {:error, :repository_unavailable}}}
    ]

    assert {:ok, %{recent_calls: %{status: :unavailable}}} =
             Vxpipe.Calls.TenantDashboard.fetch(principal(), @key, unavailable)
  end

  defp principal(overrides \\ %{}) do
    {:ok, principal} =
      Principal.new(
        Map.merge(
          %{
            user_public_id: "user",
            session_public_id: "session",
            account_kind: :member,
            grants: MapSet.new(["calls.read"]),
            assigned_tenants: %{@key => :read},
            all_tenant_actions: MapSet.new()
          },
          overrides
        )
      )

    principal
  end

  defp tenant(key), do: %Tenant{key: key, name: "Tenant", inserted_at: ~U[2026-10-13 00:00:00Z]}

  defp api_principal(scopes),
    do: %ApiPrincipal{tenant_key: @key, api_key_id: "synthetic-key", scopes: MapSet.new(scopes)}

  defp platform_actor,
    do: %InstallationOperator{
      grant: :installation_operator,
      api_key_id: "synthetic-platform-key",
      credential_kind: :platform_api_key
    }

  defp repository(result) do
    pid = start_supervised!({TestAdminRepository, result}, id: make_ref())
    [admin_repository: TestAdminRepository.admin_repository(pid)]
  end
end
