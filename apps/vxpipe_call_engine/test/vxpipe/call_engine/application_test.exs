defmodule Vxpipe.CallEngine.ApplicationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Application
  alias Vxpipe.CallEngine.Diagnostics.ModelFixture

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
end
