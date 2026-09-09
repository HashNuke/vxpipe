defmodule Vxpipe.MCP.OfficialConformanceIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 120_000

  test "passes the pinned in-scope official client scenarios" do
    output = run_fixture("test-mcp-conformance")

    assert output =~ "Passed: 1/1, 0 failed, 0 warnings"
  end

  test "resumes the corrected exact-version SSE fixture without another tool call" do
    output = run_fixture("test-mcp-sse-recovery")

    assert output =~ "Passed: 3/3, 0 failed, 0 warnings"
  end

  test "discovers and invokes the pinned Everything reference server" do
    output = run_fixture("test-mcp-everything")

    assert output =~ ~s("name":"echo")
    assert output =~ "Echo: vxpipe-reference-probe"
  end

  defp run_fixture(script) do
    project_root = Path.expand("../../../..", __DIR__)
    runner = Path.join([project_root, "bin", script])

    {output, status} =
      System.cmd(runner, [],
        cd: project_root,
        stderr_to_stdout: true,
        env: [{"NO_COLOR", "1"}]
      )

    assert status == 0, output
    output
  end
end
