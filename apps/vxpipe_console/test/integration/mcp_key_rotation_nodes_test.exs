defmodule Vxpipe.Console.MCPKeyRotationNodesTest do
  use Vxpipe.Console.Test.MCPRuntimeNodeCase, async: false

  @moduletag isolated_database: true

  alias Vxpipe.Persistence.CredentialKeyring
  alias Vxpipe.Persistence.MCP.ConnectionStore

  for grant <- ~w(authorization_code client_credentials) do
    @tag grant: grant
    test "#{grant} key retirement waits for captured old writers and a final batch", data do
      {old_writer, new_writer, only_new} = contexts(data.context)
      refute Keyword.fetch!(data.context, :repo) == Vxpipe.Persistence.Repo
      for peer <- [data.first, data.second], do: assert(:ok = rpc(peer, :context, [old_writer]))
      assert {:ok, original} = saved(data)

      hold(data, true)
      async(:renewed, fn -> rpc(data.first, :refresh, [data.tenant, data.id, 1]) end)
      assert_receive {:node_token_response, request, 200}, 5_000
      assert {:ok, claimed} = ConnectionStore.resolve(old_writer, data.tenant, data.id)
      assert is_map(claimed.secrets["refresh_claim"])

      assert {:ok, %{processed: 2, remaining_by_key: remaining}} =
               rpc(data.second, :reencrypt, [new_writer])

      assert remaining == %{}
      assert {:ok, rotated} = ConnectionStore.resolve(only_new, data.tenant, data.id)
      assert rotated == claimed

      assert {:error, :oauth_refresh_in_progress} =
               rpc(data.second, :refresh, [data.tenant, data.id, 1])

      assert tokens(data) == 1

      # Changing configuration cannot replace the context captured by this operation.
      assert :ok = rpc(data.first, :context, [new_writer])

      send(request, :release_token)
      assert_receive {:node_token_released, ^request}, 5_000
      assert_receive {:node_token_finished, ^request}, 5_000
      assert_receive {:renewed, :ok}, 5_000

      assert {:error, :credential_key_unavailable} =
               ConnectionStore.resolve(only_new, data.tenant, data.id)

      assert {:ok, completed} = ConnectionStore.resolve(old_writer, data.tenant, data.id)
      assert completed.connection == original.connection
      assert completed.secrets["grant_revision"] == 2
      assert completed.secrets["access_token"] != original.secrets["access_token"]
      refute Map.has_key?(completed.secrets, "refresh_claim")

      # The completion acknowledgement drains the old operation before changing writers.
      for peer <- [data.first, data.second], do: assert(:ok = rpc(peer, :context, [new_writer]))

      assert {:ok, %{processed: 1, remaining_by_key: remaining}} =
               rpc(data.second, :reencrypt, [new_writer])

      assert remaining == %{}

      for peer <- [data.first, data.second] do
        assert :ok = rpc(peer, :context, [only_new])
        assert {:ok, ^completed} = rpc(peer, :stored, [data.tenant, data.id])
      end

      hold(data, false)

      for {writer, revision} <- [{data.first, 2}, {data.second, 3}] do
        assert {:ok, before_renewal} = rpc(writer, :stored, [data.tenant, data.id])
        assert :ok = rpc(writer, :refresh, [data.tenant, data.id, revision])
        assert_receive {:node_token_response, _, 200}, 5_000
        assert tokens(data) == revision

        for peer <- [data.first, data.second] do
          assert {:ok, current} = rpc(peer, :stored, [data.tenant, data.id])
          assert current.connection == original.connection
          assert current.secrets["grant_revision"] == revision + 1
          assert current.secrets["access_token"] != before_renewal.secrets["access_token"]

          if data.grant == "client_credentials" do
            refute Map.has_key?(current.secrets, "refresh_token")
          else
            assert current.secrets["refresh_token"] != before_renewal.secrets["refresh_token"]
          end
        end
      end
    end
  end

  defp contexts(context) do
    {:ok, old} = CredentialKeyring.fetch(Keyword.fetch!(context, :keyring), "node-test")
    new = :crypto.strong_rand_bytes(32)
    {:ok, old_writer} = CredentialKeyring.new("node-test", %{"node-test" => old, "new" => new})
    {:ok, new_writer} = CredentialKeyring.new("new", %{"node-test" => old, "new" => new})
    {:ok, only_new} = CredentialKeyring.new("new", %{"new" => new})

    {Keyword.put(context, :keyring, old_writer), Keyword.put(context, :keyring, new_writer),
     Keyword.put(context, :keyring, only_new)}
  end
end
