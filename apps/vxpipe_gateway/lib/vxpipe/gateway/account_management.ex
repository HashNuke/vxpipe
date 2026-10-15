defmodule Vxpipe.Gateway.AccountManagement do
  @moduledoc "Shared canonical account inputs and verified-actor adaptation for HTTP and MCP."

  alias Vxpipe.Calls.InstallationOperator
  alias Vxpipe.Identity
  alias Vxpipe.Identity.{AccountInput, Accounts, ApiKeyActor, Principal, Roles}

  def authorize_machine(%InstallationOperator{} = actor) do
    with {:ok, %ApiKeyActor{}} <- identity_actor(actor), do: :ok
  end

  def authorize_machine(_actor), do: {:error, :forbidden}

  def list_users(actor, params, options \\ []) do
    with_context(actor, options, fn deps, actor ->
      with {:ok, filters} <- AccountInput.list(params),
           do: Accounts.list_users(deps, actor, filters)
    end)
  end

  def get_user(actor, id, options \\ []) do
    with_context(actor, options, fn deps, actor ->
      with :ok <- user_id(id), do: Accounts.get_user(deps, actor, id)
    end)
  end

  def create_user(actor, params, options \\ []) do
    with_context(actor, options, fn deps, actor ->
      with {:ok, attrs} <- AccountInput.create(params),
           do: Accounts.create_user(deps, actor, attrs)
    end)
  end

  def update_user(actor, id, params, options \\ []) do
    with_context(actor, options, fn deps, actor ->
      with :ok <- user_id(id),
           {:ok, attrs} <- AccountInput.update(params),
           do: Accounts.update_user(deps, actor, id, attrs)
    end)
  end

  def disable_user(actor, id, options \\ []),
    do: update_user(actor, id, %{"enabled" => false}, options)

  def list_role_options(actor, params, options \\ []) do
    with_context(actor, options, fn deps, actor ->
      with :ok <- role_fields(params),
           {:ok, filters} <- AccountInput.list(params) do
        Roles.list_role_options(deps, actor, Map.take(filters, [:page, :page_size]))
      end
    end)
  end

  defp with_context(actor, options, operation) do
    with {:ok, actor} <- identity_actor(actor),
         {:ok, deps} <- dependencies(options) do
      operation.(deps, actor)
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp identity_actor(%Principal{} = actor), do: {:ok, actor}

  defp identity_actor(%InstallationOperator{
         grant: :installation_operator,
         credential_kind: :platform_api_key,
         api_key_id: id
       }),
       do: ApiKeyActor.new(id)

  defp identity_actor(_actor), do: {:error, :forbidden}

  defp dependencies(options) do
    case Keyword.fetch(options, :identity_dependencies) do
      {:ok, dependencies} when is_map(dependencies) -> {:ok, dependencies}
      :error -> Identity.dependencies()
      _invalid -> {:error, :unavailable}
    end
  end

  defp user_id(id), do: if(ApiKeyActor.valid_id?(id), do: :ok, else: {:error, :invalid_user_id})

  defp role_fields(params) when is_map(params) do
    if Enum.all?(Map.keys(params), &(&1 in ["page", "page_size"])),
      do: :ok,
      else: {:error, :invalid_account}
  end

  defp role_fields(_params), do: {:error, :invalid_account}
end
