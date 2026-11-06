defmodule Vxpipe.Console.IntegrationsDirectory.RequestTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.IntegrationsDirectory.Request

  test "builds anonymous versioned requests and normalizes global search" do
    assert {:ok, request} =
             Request.build(:integrations, %{"q" => "  calendar  ", "scope" => "tenant"})

    assert request.url ==
             "https://integrations-api-production-2803.up.railway.app/v1/integrations"

    assert request.params == %{"q" => "calendar", "scope" => "tenant", "limit" => 20}

    assert request.headers == [
             {"accept", "application/json"},
             {"x-vxpipe-version", Application.spec(:vxpipe_console, :vsn) |> to_string()}
           ]
  end

  test "category pages preserve opaque cursors and use their own default limit" do
    assert {:ok, request} = Request.build(:categories, %{"cursor" => "opaque+/="})
    assert request.params == %{"cursor" => "opaque+/=", "limit" => 100}
  end

  test "rejects unsupported parameters instead of forwarding private local data" do
    for params <- [
          %{"tenant_id" => "private"},
          %{"authorization" => "private"},
          %{"q" => "search", "category" => "calendar"},
          %{"scope" => "other"},
          %{"limit" => 101},
          %{"limit" => "20"},
          %{"cursor" => String.duplicate("a", 2049)},
          %{"q" => String.duplicate("a", 201)}
        ] do
      assert {:error, :invalid_query} = Request.build(:integrations, params)
    end

    assert {:error, :invalid_query} = Request.build(:categories, %{"q" => "search"})
    assert {:error, :invalid_resource} = Request.build(:unknown, %{})
  end

  test "only accepts an HTTPS origin without credentials, query or path" do
    assert {:ok, request} = Request.build(:categories, %{}, "https://directory.example:8443/")
    assert request.url == "https://directory.example:8443/v1/categories"

    for origin <- [
          "http://directory.example",
          "https://user:secret@directory.example",
          "https://directory.example/path",
          "https://directory.example?token=private",
          "https://directory.example#fragment",
          "https://",
          nil
        ] do
      assert {:error, :invalid_origin} = Request.build(:categories, %{}, origin)
    end
  end

  test "category queries accept exactly the identifier grammar published by the schema" do
    for category <- ["ai", "telephony", "team--calendar", "calendar-", String.duplicate("a", 64)] do
      assert {:ok, request} = Request.build(:integrations, %{"category" => category})
      assert request.params["category"] == category
    end

    for category <- ["1calendar", "-calendar", "calendar_teams", String.duplicate("a", 65)] do
      assert {:error, :invalid_query} = Request.build(:integrations, %{"category" => category})
    end
  end
end
