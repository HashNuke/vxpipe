defmodule Vxpipe.Gateway.PhoneNumberCatalogTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Gateway.PhoneNumberCatalog

  test "Twilio lists owned voice numbers and exposes a safe pagination token" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/2010-04-01/Accounts/ACdemo/IncomingPhoneNumbers.json"
      assert conn.query_params["PhoneNumber"] == "*555*"

      Req.Test.json(conn, %{
        "incoming_phone_numbers" => [
          %{
            "sid" => "PN1",
            "phone_number" => "+15550000001",
            "friendly_name" => "Support",
            "capabilities" => %{"voice" => true}
          },
          %{
            "sid" => "PN2",
            "phone_number" => "+15550000002",
            "capabilities" => %{"voice" => false}
          }
        ],
        "next_page_uri" => "/2010-04-01/Accounts/ACdemo/IncomingPhoneNumbers.json?PageToken=next"
      })
    end)

    assert {:ok,
            %{numbers: [%{id: "PN1", number: "+15550000001", name: "Support"}], next_page: "next"}} =
             PhoneNumberCatalog.list(
               "twilio",
               "ACdemo",
               %{"account_sid" => "ACdemo", "auth_token" => "test-token"},
               "555",
               nil,
               plug: {Req.Test, __MODULE__}
             )
  end

  test "Telnyx lists active numbers only from the selected application's connection" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.query_params["filter"]["connection_id"] == "app1"
      assert conn.query_params["filter"]["status"] == "active"

      Req.Test.json(conn, %{
        "data" => [
          %{
            "id" => "1",
            "phone_number" => "+15550000001",
            "connection_id" => "app1",
            "status" => "active"
          }
        ],
        "meta" => %{"page_number" => 1, "total_pages" => 2}
      })
    end)

    assert {:ok, %{numbers: [%{number: "+15550000001"}], next_page: "2"}} =
             PhoneNumberCatalog.list("telnyx", "app1", %{"api_key" => "test-key"}, "", nil,
               plug: {Req.Test, __MODULE__}
             )
  end

  test "provider failures return a fixed error without forwarding provider bodies" do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 401, "private error") end)

    assert {:error, :phone_numbers_unavailable} =
             PhoneNumberCatalog.list("telnyx", "app1", %{"api_key" => "test-key"}, "", nil,
               plug: {Req.Test, __MODULE__}
             )
  end
end
