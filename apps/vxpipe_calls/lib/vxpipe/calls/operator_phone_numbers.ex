defmodule Vxpipe.Calls.OperatorPhoneNumbers do
  @moduledoc "Installation- or user-authorized carrier inventory with current published number assignments."
  alias Vxpipe.Calls.{
    InstallationOperator,
    ProviderAuth,
    Repositories,
    TelephonyServices,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  # Safe authoring number choices for assigned members.
  #
  # Requires exact `call_specs.write` tenant authority (never broad
  # `tenant_services.read`). The resolved service must be tenant-pinned and
  # tenant-owned unless the author may reference platform services. The
  # credential payload stays inside the reader closure; output is limited to
  # public number inventory plus publication availability, with no secrets,
  # ingress keys, or credential ids.
  def list(%UserPrincipal{} = principal, tenant, service, query, options) when is_list(options) do
    with :ok <- ProviderAuth.tenant_key(tenant),
         :ok <- UserAuthorization.authorize_tenant(principal, "call_specs.write", tenant),
         :ok <- validate_query(query),
         {:ok, snapshot} <- TelephonyServices.resolve(tenant, service, options),
         true <- snapshot.service.tenant_key == tenant,
         :ok <- authorize_service_visibility(principal, tenant, snapshot.service),
         {:ok, reader} <- Keyword.fetch(options, :number_reader),
         {:ok, page} <- reader.(snapshot, query),
         {:ok, numbers} <- validate_page(page),
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, assignments} <-
           Repositories.call(repository, :list_number_assignments, [
             tenant,
             Enum.map(numbers, & &1.number)
           ]),
         {:ok, valid_assignments} <- validate_assignments(assignments) do
      excluded = Map.get(query, :call_spec_id)

      by_number =
        valid_assignments
        |> Enum.reject(&(&1.call_spec_id == excluded))
        |> Enum.group_by(& &1.number)

      safe_numbers =
        Enum.map(numbers, fn number ->
          used = Map.get(by_number, number.number, [])

          %{
            id: number.id,
            number: number.number,
            name: number.name,
            available: used == [],
            assigned_to: Enum.map(used, & &1.name)
          }
        end)

      {:ok, %{numbers: safe_numbers, next_page: page.next_page}}
    else
      :error -> {:error, :phone_numbers_unavailable}
      false -> {:error, :phone_numbers_unavailable}
      {:error, _} = error -> error
    end
  end

  def list(%InstallationOperator{grant: :installation_operator}, tenant, service, query, options) do
    with :ok <- ProviderAuth.tenant_key(tenant),
         :ok <- validate_query(query),
         {:ok, snapshot} <- TelephonyServices.resolve(tenant, service, options),
         {:ok, reader} <- Keyword.fetch(options, :number_reader),
         {:ok, page} <- reader.(snapshot, query),
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, assignments} <-
           Repositories.call(repository, :list_number_assignments, [
             tenant,
             Enum.map(page.numbers, & &1.number)
           ]) do
      excluded = Map.get(query, :call_spec_id)

      by_number =
        assignments |> Enum.reject(&(&1.call_spec_id == excluded)) |> Enum.group_by(& &1.number)

      numbers =
        Enum.map(page.numbers, fn number ->
          used = Map.get(by_number, number.number, [])
          Map.merge(number, %{available: used == [], assigned_to: Enum.map(used, & &1.name)})
        end)

      {:ok, %{numbers: numbers, next_page: page.next_page}}
    else
      :error -> {:error, :phone_numbers_unavailable}
      {:error, _} = error -> error
    end
  end

  def list(_, _, _, _, _), do: {:error, :installation_operator_required}

  defp validate_query(%{search: search, page: page} = query)
       when is_binary(search) and byte_size(search) <= 64 do
    if (is_nil(page) or (is_binary(page) and byte_size(page) in 1..256)) and
         (is_nil(Map.get(query, :call_spec_id)) or
            (is_binary(query.call_spec_id) and byte_size(query.call_spec_id) <= 128)),
       do: :ok,
       else: {:error, :invalid_request}
  end

  defp validate_query(_), do: {:error, :invalid_request}

  defp authorize_service_visibility(principal, tenant_key, service) do
    privileged? = UserAuthorization.platform_authoring_allowed?(principal)

    allowed? =
      if privileged?,
        do: service.credential_owner in [nil, {:tenant, tenant_key}, :platform],
        else: service.credential_owner in [nil, {:tenant, tenant_key}]

    if allowed?, do: :ok, else: {:error, :phone_numbers_unavailable}
  end

  defp validate_page(%{numbers: numbers, next_page: next_page})
       when is_list(numbers) and length(numbers) <= 50 do
    if Enum.all?(numbers, &valid_number?/1) and
         (is_nil(next_page) or (is_binary(next_page) and byte_size(next_page) in 1..256)) do
      {:ok, Enum.map(numbers, &Map.take(&1, [:id, :number, :name]))}
    else
      {:error, :phone_numbers_unavailable}
    end
  end

  defp validate_page(_invalid), do: {:error, :phone_numbers_unavailable}

  defp valid_number?(%{id: id, number: number, name: name}) do
    is_binary(id) and byte_size(id) in 1..128 and is_binary(number) and
      byte_size(number) in 2..16 and is_binary(name) and byte_size(name) in 1..128
  end

  defp valid_number?(_invalid), do: false

  defp validate_assignments(assignments) when is_list(assignments) do
    if Enum.all?(assignments, &valid_assignment?/1) do
      {:ok, Enum.map(assignments, &Map.take(&1, [:number, :call_spec_id, :name]))}
    else
      {:error, :phone_numbers_unavailable}
    end
  end

  defp validate_assignments(_invalid), do: {:error, :phone_numbers_unavailable}

  defp valid_assignment?(%{number: number, call_spec_id: id, name: name}) do
    is_binary(number) and byte_size(number) in 2..16 and is_binary(id) and
      byte_size(id) in 1..128 and is_binary(name) and byte_size(name) in 1..128
  end

  defp valid_assignment?(_invalid), do: false
end
