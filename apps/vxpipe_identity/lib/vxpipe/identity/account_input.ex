defmodule Vxpipe.Identity.AccountInput do
  @moduledoc "Strict canonical account inputs shared by HTTP and MCP adapters."
  alias Vxpipe.Identity.{AccountPage, ApiKeyActor, Email, Password}

  @create ~w(email password password_confirmation role_id memberships)
  @update ~w(email role_id memberships enabled)

  def create(params) when is_map(params) do
    with :ok <- fields(params, @create),
         true <-
           Enum.all?(~w(email password password_confirmation role_id), &Map.has_key?(params, &1)),
         {:ok, attrs} <- normalize(params),
         :ok <- Password.confirm(attrs.password, attrs.password_confirmation) do
      {:ok, Map.put_new(attrs, :memberships, %{})}
    else
      false -> {:error, :invalid_account}
      error -> error
    end
  end

  def create(_params), do: {:error, :invalid_account}

  def update(params) when is_map(params) and map_size(params) > 0 do
    with :ok <- fields(params, @update), do: normalize(params)
  end

  def update(_params), do: {:error, :invalid_account}

  def list(params) when is_map(params) do
    with :ok <- fields(params, ~w(page page_size query role_id)),
         {:ok, page} <- number(Map.get(params, "page", 1)),
         {:ok, size} <- number(Map.get(params, "page_size", 25)),
         :ok <- optional_id(params, "role_id"),
         :ok <- optional_query(params) do
      AccountPage.filters(%{
        page: page,
        page_size: size,
        search: Map.get(params, "query"),
        role_public_id: Map.get(params, "role_id")
      })
    end
  end

  def list(_params), do: {:error, :invalid_account}

  defp normalize(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn {key, value}, {:ok, attrs} ->
      case field(key, value) do
        {:ok, name, normalized} -> {:cont, {:ok, Map.put(attrs, name, normalized)}}
        error -> {:halt, error}
      end
    end)
  end

  defp field("email", value) do
    with {:ok, _} <- Email.normalize(value), do: {:ok, :email, String.trim(value)}
  end

  defp field("role_id", value) do
    if ApiKeyActor.valid_id?(value),
      do: {:ok, :role_public_id, value},
      else: {:error, :invalid_role_filter}
  end

  defp field("enabled", value) when is_boolean(value), do: {:ok, :disabled, not value}
  defp field("password", value) when is_binary(value), do: {:ok, :password, value}

  defp field("password_confirmation", value) when is_binary(value),
    do: {:ok, :password_confirmation, value}

  defp field("memberships", value) do
    with {:ok, memberships} <- memberships(value), do: {:ok, :memberships, memberships}
  end

  defp field(_key, _value), do: {:error, :invalid_account}

  defp memberships(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn
      %{"tenant_key" => key, "access" => access} = entry, {:ok, acc}
      when map_size(entry) == 2 and is_binary(key) and access in ["read", "read_write"] ->
        if Regex.match?(~r/\A[A-Za-z0-9_-]{16}\z/, key) and not Map.has_key?(acc, key),
          do: {:cont, {:ok, Map.put(acc, key, access)}},
          else: {:halt, {:error, :invalid_memberships}}

      _, _ ->
        {:halt, {:error, :invalid_memberships}}
    end)
  end

  defp memberships(_entries), do: {:error, :invalid_memberships}

  defp fields(params, allowed) do
    if Enum.all?(Map.keys(params), &(&1 in allowed)), do: :ok, else: {:error, :invalid_account}
  end

  defp number(value) when is_integer(value), do: {:ok, value}

  defp number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, :invalid_pagination}
    end
  end

  defp number(_value), do: {:error, :invalid_pagination}

  defp optional_id(params, key) do
    if not Map.has_key?(params, key) or ApiKeyActor.valid_id?(Map.get(params, key)),
      do: :ok,
      else: {:error, :invalid_role_filter}
  end

  defp optional_query(params) do
    if not Map.has_key?(params, "query") or is_binary(Map.get(params, "query")),
      do: :ok,
      else: {:error, :invalid_search}
  end
end
