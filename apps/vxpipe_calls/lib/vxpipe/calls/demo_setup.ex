defmodule Vxpipe.Calls.DemoSetup do
  @moduledoc "Installation-operator workflow for the durable first demo tenant."

  alias Vxpipe.Calls.{InstallationOperator, PublicId, Repositories, Tenant}

  @tenant_name "DemoTenant"
  @maximum_attempts 4

  @spec ensure_tenant(InstallationOperator.t(), keyword()) ::
          {:ok, Tenant.t()} | {:error, term()}
  def ensure_tenant(authority, options \\ [])

  def ensure_tenant(
        %InstallationOperator{grant: :installation_operator},
        options
      )
      when is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :demo_tenant_repository) do
      ensure(repository, options, @maximum_attempts)
    end
  end

  def ensure_tenant(%InstallationOperator{}, _options),
    do: {:error, :installation_operator_required}

  def ensure_tenant(_authority, _options), do: {:error, :installation_operator_required}

  defp ensure(_repository, _options, 0), do: {:error, :identifier_generation_exhausted}

  defp ensure(repository, options, attempts_left) do
    candidate = %Tenant{
      key: generate(options, :tenant_key_generator, &PublicId.tenant_key/0),
      name: @tenant_name,
      inserted_at: Keyword.get(options, :now, DateTime.utc_now())
    }

    case Repositories.call(repository, :ensure, [candidate]) do
      {:error, :tenant_key_conflict} -> ensure(repository, options, attempts_left - 1)
      result -> result
    end
  end

  defp generate(options, key, fallback) do
    options
    |> Keyword.get(key, fallback)
    |> then(& &1.())
  end
end
