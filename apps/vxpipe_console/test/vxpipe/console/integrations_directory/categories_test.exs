defmodule Vxpipe.Console.IntegrationsDirectory.CategoriesTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.IntegrationsDirectory.Categories
  alias Vxpipe.Console.Test.FakeUserIdentity

  test "collects category pages without exposing tenant information" do
    owner = self()

    fetcher = fn :categories, params ->
      send(owner, {:public_query, params})

      case params["cursor"] do
        nil -> {:ok, %{body: page("calendar", "next")}}
        "next" -> {:ok, %{body: page("crm", nil)}}
      end
    end

    assert {:ok, %{categories: [%{"id" => "calendar"}, %{"id" => "crm"}]}} =
             Categories.list(FakeUserIdentity.principal(), "AAAAAAAAAAAAAAAA", fetcher: fetcher)

    assert_receive {:public_query, %{"limit" => 100}}
    assert_receive {:public_query, %{"limit" => 100, "cursor" => "next"}}
  end

  test "rejects repeated cursors and mixed snapshots instead of a partial sidebar" do
    assert {:error, :invalid_page} =
             Categories.list(FakeUserIdentity.principal(), "AAAAAAAAAAAAAAAA",
               fetcher: fn _, _ -> {:ok, %{body: page("calendar", "same")}} end
             )

    assert {:error, :invalid_page} =
             Categories.list(FakeUserIdentity.principal(), "AAAAAAAAAAAAAAAA",
               fetcher: fn _, params ->
                 body =
                   if params["cursor"],
                     do: Map.put(page("crm", nil), "revision", "different"),
                     else: page("calendar", "next")

                 {:ok, %{body: body}}
               end
             )
  end

  test "requires tenant read access before fetching" do
    principal = %{
      FakeUserIdentity.principal()
      | account_kind: :member,
        grants: MapSet.new(),
        all_tenant_actions: MapSet.new()
    }

    assert {:error, :forbidden} =
             Categories.list(principal, "AAAAAAAAAAAAAAAA",
               fetcher: fn _, _ -> flunk("unauthorized discovery") end
             )
  end

  defp page(id, cursor) do
    %{
      "directory_id" => "directory",
      "revision" => "one",
      "installation_version" => "0.1.0",
      "items" => [%{"id" => id, "name" => id, "order" => 10, "integration_count" => 1}],
      "pagination" => %{"next_cursor" => cursor}
    }
  end
end
