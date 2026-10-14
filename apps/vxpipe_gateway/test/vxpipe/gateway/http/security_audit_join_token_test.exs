defmodule Vxpipe.Gateway.HTTP.SecurityAuditJoinTokenTest do
  # Findings from the 2026-10-14 security audit. Tests tagged :security_open assert
  # the secure behaviour and fail until their fix lands; run them with
  # `mix test --only security_open`. See labnotes/milestones/security-audit-remediation.md.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.TestAdmissionBackend

  @api_key "vxp_test-only-gateway-key"
  @join_token "vxj_test-only-gateway-token"

  setup do
    backend =
      start_supervised!(
        {TestAdmissionBackend, api_key: @api_key, join_token: @join_token, observer: self()}
      )

    endpoint =
      Endpoint.init(
        cors: [
          allowed_origins: [],
          allowed_methods: ["POST", "OPTIONS"],
          allowed_headers: ["content-type", "authorization"],
          allow_credentials: false
        ],
        call_admission: [enabled: true, backend: TestAdmissionBackend.backend(backend)]
      )

    [endpoint: endpoint]
  end

  # SEC-3: join tokens are bearer credentials for a live call, but their lifetime has
  # only a 300-second floor, so a request can mint a token valid for centuries.
  @tag :security_open
  test "rejects a join-token lifetime beyond one day", context do
    for path <- [prepare_path(), token_path()] do
      conn =
        :post
        |> conn(path, JSON.encode!(%{"join_token_ttl_seconds" => 100 * 365 * 86_400}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{@api_key}")
        |> Endpoint.call(context.endpoint)

      assert conn.status == 400, "#{path} accepted a 100-year join token"
    end
  end

  defp prepare_path do
    "/api/tenants/#{TestAdmissionBackend.tenant_key()}/participants/#{TestAdmissionBackend.participant_key()}/calls"
  end

  defp token_path do
    "/api/tenants/#{TestAdmissionBackend.tenant_key()}/calls/#{TestAdmissionBackend.call_id()}/participants/#{TestAdmissionBackend.participant_key()}/join-tokens"
  end
end
