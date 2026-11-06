defmodule Vxpipe.Console.IntegrationsDirectory.ListingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.IntegrationsDirectory.{Listing, Request}

  test "resolves an exact public reference through the existing tenant list request" do
    owner = self()
    page = page()
    [item] = page["items"]
    reference = Listing.reference(page, item, %{"category" => "calendar", "limit" => 20})

    assert reference == %{
             "directory_id" => "example-directory",
             "integration_id" => "calendar",
             "entry_revision" => 3,
             "page" => %{"category" => "calendar", "limit" => 20, "scope" => "tenant"}
           }

    fetcher = fn resource, params ->
      send(owner, {:request, resource, params})
      {:ok, %{body: page}}
    end

    assert {:ok, snapshot} = Listing.resolve(reference, fetcher: fetcher)
    assert snapshot["directory_id"] == "example-directory"
    assert snapshot["integration_id"] == "calendar"
    assert snapshot["revision"] == 3
    assert snapshot["name"] == "Calendar"
    assert snapshot["endpoint"] == "https://calendar.example.test/mcp"
    assert snapshot["authentication"] == %{"type" => "bearer"}
    assert_receive {:request, :integrations, params}
    assert params == reference["page"]
  end

  test "invalid references and private parameters fail before any directory request" do
    reference = reference()

    for invalid <- [
          nil,
          Map.put(reference, "endpoint", "https://attacker.example.test/mcp"),
          Map.put(reference, "authentication", %{"type" => "none"}),
          Map.put(reference, "directory_id", "../other"),
          Map.put(reference, "integration_id", String.duplicate("a", 65)),
          Map.put(reference, "entry_revision", 0),
          Map.put(reference, "entry_revision", "3"),
          Map.put(reference, "page", nil),
          put_in(reference, ["page", "scope"], "platform"),
          put_in(reference, ["page", "tenant_key"], "private-tenant"),
          put_in(reference, ["page", "credentials"], %{"token" => "private-token"}),
          put_in(reference, ["page", "q"], "query-with-category")
        ] do
      assert {:error, :invalid_mcp_listing} =
               Listing.resolve(invalid,
                 fetcher: fn _, _ -> flunk("invalid reference must not reach the directory") end
               )
    end
  end

  test "rejects changed identity, entry revision, retired entries and incompatible releases" do
    page = page()

    for invalid <- [
          Map.put(page, "directory_id", "other-directory"),
          update_item(page, &Map.put(&1, "id", "other-entry")),
          update_item(page, &Map.put(&1, "revision", 4)),
          update_item(page, &Map.put(&1, "availability", "retired")),
          update_item(page, &Map.put(&1, "minimum_vxpipe_version", "99.0.0")),
          Map.put(page, "installation_version", "99.0.0"),
          put_in(page, ["query", "category"], "other-category")
        ] do
      assert {:error, :mcp_listing_unavailable} = resolve(invalid)
    end
  end

  test "preserves the request identity for later pages and enforces its revision" do
    page =
      page()
      |> Map.put("pagination", %{
        "limit" => 20,
        "total_items" => 21,
        "start_index" => 21,
        "end_index" => 21,
        "next_cursor" => nil,
        "previous_cursor" => "previous"
      })

    reference =
      reference()
      |> put_in(["page", "cursor"], "opaque-cursor")
      |> put_in(["page", "revision"], "catalog-revision")

    assert {:ok, _} =
             Listing.resolve(reference,
               fetcher: fn :integrations, params ->
                 assert params == reference["page"]
                 {:ok, %{body: page}}
               end
             )

    assert {:error, :mcp_listing_unavailable} =
             Listing.resolve(reference,
               fetcher: fn _, _ -> {:ok, %{body: Map.put(page, "revision", "changed")}} end
             )
  end

  test "projects only public recipe fields and independently optional setup content" do
    page =
      update_item(page(), fn item ->
        item
        |> Map.put("setup_notes", "Get a key from your account.")
        |> Map.put("setup_url", "https://calendar.example.test/setup")
        |> Map.put("documentation_url", "https://calendar.example.test/docs")
        |> Map.put("unknown_private_data", "untrusted-marker")
        |> put_in(["connection", "authentication", "client_secret"], "untrusted-marker")
      end)

    assert {:ok, snapshot} = resolve(page)
    assert snapshot["setup_notes"] == "Get a key from your account."
    assert snapshot["setup_url"] == "https://calendar.example.test/setup"
    assert snapshot["documentation_url"] == "https://calendar.example.test/docs"
    refute inspect(snapshot) =~ "untrusted-marker"

    for key <- ~w(setup_notes setup_url documentation_url) do
      assert {:ok, snapshot} = resolve(update_item(page, &Map.delete(&1, key)))
      refute Map.has_key?(snapshot, key)
    end
  end

  test "only executable authentication recipes are accepted" do
    for recipe <- [
          %{"type" => "none"},
          %{"type" => "bearer"},
          %{"type" => "basic"},
          %{"type" => "api_key", "header_name" => "X-API-Key"},
          %{"type" => "oauth2", "registration" => "discover", "scopes" => ["calendar:read"]},
          %{"type" => "oauth2", "registration" => "cimd"},
          %{"type" => "oauth2", "registration" => "dcr"},
          %{"type" => "oauth2", "registration" => "preregistered"}
        ] do
      assert {:ok, snapshot} =
               resolve(update_item(page(), &put_in(&1, ["connection", "authentication"], recipe)))

      assert snapshot["authentication"] == recipe
    end

    for recipe <- [
          %{"type" => "unknown"},
          %{"type" => "api_key", "header_name" => "Host"},
          %{"type" => "api_key", "header_name" => "MCP-Session-Id"},
          %{"type" => "oauth2", "registration" => "discover", "scopes" => ["two scopes"]}
        ] do
      assert {:error, :mcp_listing_unavailable} =
               resolve(update_item(page(), &put_in(&1, ["connection", "authentication"], recipe)))
    end
  end

  test "unsafe setup links cannot become clickable snapshot links" do
    for key <- ~w(setup_url documentation_url),
        url <- ["https://user:password@calendar.example.test/docs", "https://:443/docs"] do
      assert {:error, :mcp_listing_unavailable} =
               resolve(update_item(page(), &Map.put(&1, key, url)))
    end
  end

  test "outages and expired cursors never use browser-supplied or stale template data" do
    for error <- [
          :unavailable,
          :cursor_expired,
          :unsupported_version,
          :busy,
          {:private, "marker"}
        ] do
      assert {:error, :mcp_listing_unavailable} =
               Listing.resolve(reference(), fetcher: fn _, _ -> {:error, error} end)
    end

    assert {:error, :mcp_listing_unavailable} =
             Listing.resolve(reference(), fetcher: fn _, _ -> exit(:noproc) end)
  end

  defp resolve(page),
    do: Listing.resolve(reference(), fetcher: fn _, _ -> {:ok, %{body: page}} end)

  defp reference do
    %{
      "directory_id" => "example-directory",
      "integration_id" => "calendar",
      "entry_revision" => 3,
      "page" => %{"category" => "calendar", "limit" => 20, "scope" => "tenant"}
    }
  end

  defp update_item(page, fun), do: Map.update!(page, "items", &Enum.map(&1, fun))

  defp page do
    %{
      "schema_version" => 1,
      "directory_id" => "example-directory",
      "revision" => "catalog-revision",
      "resource" => "integrations",
      "installation_version" => Request.installation_version(),
      "query" => %{"q" => "", "category" => "calendar", "scope" => "tenant"},
      "items" => [
        %{
          "id" => "calendar",
          "kind" => "mcp",
          "revision" => 3,
          "name" => "Calendar",
          "category_ids" => ["calendar"],
          "availability" => "available",
          "connection" => %{
            "type" => "mcp",
            "transport" => "streamable_http",
            "endpoint" => "https://calendar.example.test/mcp",
            "authentication" => %{"type" => "bearer"}
          }
        }
      ],
      "pagination" => %{
        "limit" => 20,
        "total_items" => 1,
        "start_index" => 1,
        "end_index" => 1,
        "next_cursor" => nil,
        "previous_cursor" => nil
      }
    }
  end
end
