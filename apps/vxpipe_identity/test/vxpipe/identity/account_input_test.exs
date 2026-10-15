defmodule Vxpipe.Identity.AccountInputTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Identity.AccountInput
  @role "11111111-1111-4111-8111-111111111111"

  test "create requires confirmation and maps only public membership keys" do
    input = %{
      "email" => "example@test.com",
      "role_id" => @role,
      "password" => "correct horse 15!",
      "password_confirmation" => "correct horse 15!"
    }

    assert {:ok, %{role_public_id: @role, memberships: %{}}} = AccountInput.create(input)
    assert {:error, _} = AccountInput.create(Map.delete(input, "password_confirmation"))
    assert {:error, _} = AccountInput.create(Map.put(input, "enabled", false))
    entry = %{"tenant_key" => "AAAAAAAAAAAAAAAA", "access" => "read"}

    assert {:ok, %{memberships: %{"AAAAAAAAAAAAAAAA" => "read"}}} =
             AccountInput.create(Map.put(input, "memberships", [entry]))

    assert {:error, :invalid_memberships} =
             AccountInput.create(Map.put(input, "memberships", [entry, entry]))

    assert {:error, :invalid_memberships} =
             AccountInput.create(
               Map.put(input, "memberships", [
                 %{"tenant_id" => "AAAAAAAAAAAAAAAA", "access" => "read"}
               ])
             )
  end

  test "updates preserve omissions and reject nulls passwords and authority fields" do
    assert {:ok, %{email: "new@test.com"}} = AccountInput.update(%{"email" => "new@test.com"})
    assert {:ok, %{disabled: false}} = AccountInput.update(%{"enabled" => true})

    assert {:ok, %{disabled: true, memberships: %{}}} =
             AccountInput.update(%{"enabled" => false, "memberships" => []})

    for input <- [
          %{},
          %{"enabled" => nil},
          %{"enabled" => "true"},
          %{"role_id" => nil},
          %{"memberships" => nil},
          %{"password" => "x"},
          %{"actor_api_key_public_id" => @role}
        ] do
      assert {:error, _} = AccountInput.update(input)
    end
  end

  test "list inputs share bounded page and account-search rules" do
    assert {:ok, %{page: 2, page_size: 10, search: "text", role_public_id: @role}} =
             AccountInput.list(%{
               "page" => "2",
               "page_size" => 10,
               "query" => " text ",
               "role_id" => @role
             })

    for input <- [
          %{"page" => 0},
          %{"page_size" => 51},
          %{"page" => 2_147_483_648},
          %{"role_id" => nil},
          %{"unknown" => 1},
          %{"query" => String.duplicate("a", 121)}
        ] do
      assert {:error, _} = AccountInput.list(input)
    end
  end
end
