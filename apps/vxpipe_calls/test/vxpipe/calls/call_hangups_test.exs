defmodule Vxpipe.Calls.CallHangupsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{InstallationOperator, Principal}
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  @tenant "AAAAAAAAAAAAAAAA"
  @call "11111111-1111-4111-8111-111111111111"
  @now ~U[2026-10-15 16:00:00.000000Z]

  test "actual calls, platform and browser authority reach only the selected tenant" do
    actors = [
      %Principal{tenant_key: @tenant, api_key_id: "key", scopes: MapSet.new([:calls])},
      %InstallationOperator{
        grant: :installation_operator,
        credential_kind: :platform_api_key,
        api_key_id: "key"
      },
      %UserPrincipal{
        user_public_id: "user",
        session_public_id: "session",
        account_kind: :member,
        grants: MapSet.new(["calls.write"]),
        assigned_tenants: %{@tenant => :read_write},
        all_tenant_actions: MapSet.new()
      }
    ]

    for actor <- actors do
      assert {:error, :not_found} =
               Calls.request_call_hangup(actor, @tenant, @call, options({:error, :not_found}))

      assert_received {:hangup_requested, @tenant, @call, @now}
    end

    for actor <- [
          %{hd(actors) | scopes: MapSet.new([:admin])},
          InstallationOperator.authority(),
          nil
        ] do
      assert {:error, :not_authorized} =
               Calls.request_call_hangup(actor, @tenant, @call, options(:must_not_call))
    end

    assert {:error, :tenant_access_forbidden} =
             Calls.request_call_hangup(
               hd(actors),
               "BBBBBBBBBBBBBBBB",
               @call,
               options(:must_not_call)
             )

    refute_received {:hangup_requested, _, _, _}
  end

  test "invalid identifiers or request timestamps fail before storage" do
    actor = %Principal{tenant_key: @tenant, api_key_id: "key", scopes: MapSet.new([:calls])}

    for id <- [nil, "", "bad\nidentifier", String.duplicate("a", 257)] do
      assert {:error, :invalid_call_hangup} =
               Calls.request_call_hangup(actor, @tenant, id, options(:must_not_call))
    end

    for clock <- [nil, "today"] do
      assert {:error, :invalid_call_hangup} =
               Calls.request_call_hangup(
                 actor,
                 @tenant,
                 @call,
                 Keyword.put(options(:must_not_call), :now, clock)
               )
    end

    refute_received {:hangup_requested, _, _, _}
  end

  test "unavailable repositories and private exceptions return a fixed failure" do
    actor = %Principal{tenant_key: @tenant, api_key_id: "key", scopes: MapSet.new([:calls])}

    for response <- [
          :raise,
          :throw,
          :exit,
          {:error, {:private, "backend-sentinel"}},
          {:ok, %{id: @call}}
        ] do
      assert {:error, :call_hangup_unavailable} =
               Calls.request_call_hangup(actor, @tenant, @call, options(response))
    end
  end

  def request_call_hangup({_owner, :must_not_call}, _tenant, _id, _now),
    do: flunk("unauthorized or invalid storage access")

  def request_call_hangup({_owner, :raise}, _tenant, _id, _now), do: raise("backend-sentinel")
  def request_call_hangup({_owner, :throw}, _tenant, _id, _now), do: throw(:private)
  def request_call_hangup({_owner, :exit}, _tenant, _id, _now), do: exit(:private)

  def request_call_hangup({owner, response}, tenant, id, now) do
    send(owner, {:hangup_requested, tenant, id, now})
    response
  end

  defp options(response),
    do: [call_repository: {__MODULE__, {self(), response}}, now: @now]
end
