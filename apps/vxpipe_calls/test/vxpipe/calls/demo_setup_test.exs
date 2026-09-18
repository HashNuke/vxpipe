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
    assert first.name == "DemoTenant"
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

  test "requires installation operator authority and a configured repository", context do
    assert {:error, :installation_operator_required} =
             DemoSetup.ensure_tenant(%InstallationOperator{grant: :invalid}, context.options)

    assert {:error, :installation_operator_required} =
             DemoSetup.ensure_tenant(:anonymous, context.options)

    assert {:error, :repository_unavailable} =
             DemoSetup.ensure_tenant(InstallationOperator.authority(), [])
  end
end
