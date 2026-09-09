defmodule Vxpipe.MCP.OfficialConformanceIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 120_000

  test "passes the pinned in-scope official client scenarios" do
    project_root = Path.expand("../../../..", __DIR__)
    runner = Path.join(project_root, "bin/test-mcp-conformance")

    {output, status} =
      System.cmd(runner, [],
        cd: project_root,
        stderr_to_stdout: true,
        env: [{"NO_COLOR", "1"}]
      )

    assert status == 0, output
    assert output =~ "Passed: 1/1, 0 failed, 0 warnings"
  end
end
