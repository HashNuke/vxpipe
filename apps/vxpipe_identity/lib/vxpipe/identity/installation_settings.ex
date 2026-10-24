defmodule Vxpipe.Identity.InstallationSettings do
  @moduledoc "Superadmin installation settings and the trusted public origin read port."
  alias Vxpipe.Identity.{InstallationURL, InstallationURLCache, Principal}

  def public_url do
    with {:ok, deps} <- Vxpipe.Identity.dependencies() do
      case Map.get(deps, :installation_url_cache) do
        nil ->
          with {:ok, installation} <- deps.installations.fetch(),
               do: {:ok, Map.get(installation, :public_url)}

        cache ->
          InstallationURLCache.fetch(cache)
      end
    end
  end

  @doc false
  def invalidate_public_url(deps) do
    if cache = Map.get(deps, :installation_url_cache), do: InstallationURLCache.invalidate(cache)
    :ok
  end

  def fetch(deps, actor) do
    with :ok <- authorize(actor),
         {:ok, installation} <- deps.installations.fetch() do
      {:ok,
       %{
         public_url: Map.get(installation, :public_url),
         revision: Map.get(installation, :public_url_revision, 0)
       }}
    end
  end

  def update(deps, actor, value, revision) do
    with :ok <- authorize(actor),
         {:ok, url} <- InstallationURL.normalize(value),
         true <- is_integer(revision) and revision >= 0 do
      result =
        if Code.ensure_loaded?(deps.installations) and
             function_exported?(deps.installations, :update_public_url, 3),
           do: deps.installations.update_public_url(actor, url, revision),
           else: {:error, :unavailable}

      if match?({:ok, _settings}, result), do: invalidate_public_url(deps)
      result
    else
      false -> {:error, :invalid_revision}
      error -> error
    end
  end

  def authorize(%Principal{account_kind: :superadmin, credential_kind: :browser_session}), do: :ok
  def authorize(_), do: {:error, :forbidden}
end
