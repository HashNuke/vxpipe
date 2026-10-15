defmodule Vxpipe.Calls.DemoSetupTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{DemoSetup, InstallationOperator}
  alias Vxpipe.Calls.TestDemoTenantRepository

  setup do
    repository = start_supervised!(TestDemoTenantRepository)

    options = [
      demo_tenant_repository: TestDemoTenantRepository.repository(repository),
      tenant_key_generator: fn -> "DEMOabcdefgh1234" end,
      now: ~U[2026-09-18 05:00:00Z]
    ]

    [options: options, repository: repository]
  end

  test "creates DemoTenant once and resumes the durable binding", context do
    authority = InstallationOperator.authority()

    assert {:ok, first} = DemoSetup.ensure_tenant(authority, context.options)
    assert first.name == "Demo"
    assert first.key == "DEMOabcdefgh1234"
    assert first.inserted_at == ~U[2026-09-18 05:00:00Z]

    assert {:ok, second} =
             DemoSetup.ensure_tenant(
               authority,
               Keyword.put(context.options, :tenant_key_generator, fn -> "OTHERabcdefgh123" end)
             )

    assert second == first
    assert TestDemoTenantRepository.candidates(context.repository) == [first]
  end

  test "browser tenant creators resume the same binding without implicit grants", context do
    actor = %Vxpipe.Identity.Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["tenants.write"])
    }

    assert {:ok, tenant} = DemoSetup.ensure_tenant(actor, context.options)
    assert {:ok, ^tenant} = DemoSetup.ensure_tenant(actor, context.options)
    assert TestDemoTenantRepository.candidates(context.repository) == [tenant]
  end

  test "browser denial is enforced before repository access", context do
    actor = %Vxpipe.Identity.Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new()
    }

    assert {:error, :forbidden} = DemoSetup.ensure_tenant(actor, [])
    assert {:error, :forbidden} = DemoSetup.ensure_tenant(actor, context.options)
    assert TestDemoTenantRepository.candidates(context.repository) == []
  end

  test "requires installation operator authority and a configured repository", context do
    assert {:error, :installation_operator_required} =
             DemoSetup.ensure_tenant(%InstallationOperator{grant: :invalid}, context.options)

    assert {:error, :installation_operator_required} =
             DemoSetup.ensure_tenant(:anonymous, context.options)

    assert {:error, :repository_unavailable} =
             DemoSetup.ensure_tenant(InstallationOperator.authority(), [])
  end
end
