defmodule Vxpipe.CallEngine.ApplicationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Application
  alias Vxpipe.CallEngine.Diagnostics.ModelFixture
  alias Vxpipe.CallEngine.OpeningAudio.AssetCache
  alias Vxpipe.CallEngine.RemoteMCP.CatalogRefresher

  test "does not supervise the retired Jido runtime" do
    settings = Elixir.Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    refute Enum.any?(Application.child_specs(settings), fn
             Vxpipe.CallEngine.Jido -> true
             _child -> false
           end)
  end

  test "supervises the model fixture only when application configuration enables it" do
    settings = Elixir.Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    enabled =
      Keyword.put(settings, :model_fixture,
        enabled: true,
        default_scenario: :success,
        delay_ms: 1_500,
        response: "Local fixture response."
      )

    disabled = Keyword.put(settings, :model_fixture, enabled: false)

    assert Enum.any?(Application.child_specs(enabled), fn
             {ModelFixture, options} -> Keyword.get(options, :name) == ModelFixture
             _child -> false
           end)

    refute Enum.any?(Application.child_specs(disabled), fn
             {ModelFixture, _options} -> true
             _child -> false
           end)
  end

  test "supervises the remote MCP refresher only when application configuration enables it" do
    settings = Elixir.Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    enabled =
      Keyword.put(settings, :remote_mcp,
        enabled: true,
        refresh_interval_ms: 60_000,
        stale_after_ms: 300_000,
        refresh_timeout_ms: 30_000
      )

    disabled = Keyword.put(settings, :remote_mcp, enabled: false)

    assert Enum.any?(Application.child_specs(enabled), fn
             {Task.Supervisor, options} ->
               Keyword.get(options, :name) ==
                 Vxpipe.CallEngine.RemoteMCP.CatalogRefreshTaskSupervisor

             _child ->
               false
           end)

    assert Enum.any?(Application.child_specs(enabled), fn
             {CatalogRefresher, options} ->
               Keyword.get(options, :name) == CatalogRefresher

             _child ->
               false
           end)

    refute Enum.any?(Application.child_specs(disabled), fn
             {CatalogRefresher, _options} -> true
             _child -> false
           end)
  end

  test "supervises one explicitly named bounded opening-asset cache" do
    settings = Elixir.Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    configured =
      Keyword.put(settings, :opening_audio,
        cache: [maximum_entries: 128, maximum_bytes: 67_108_864]
      )

    assert Enum.any?(Application.child_specs(configured), fn
             {AssetCache, options} ->
               Keyword.get(options, :name) == AssetCache and
                 Keyword.get(options, :maximum_entries) == 128 and
                 Keyword.get(options, :maximum_bytes) == 67_108_864

             _child ->
               false
           end)
  end
end
